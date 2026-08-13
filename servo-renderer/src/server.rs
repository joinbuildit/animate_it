use std::collections::HashMap;
use std::convert::Infallible;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use tokio::sync::Mutex;
use tokio_stream::StreamExt;
use tokio_stream::wrappers::ReceiverStream;

use crate::protocol::{
    BatchResponse, CancelResponse, CaptureRequest, ErrorBody, ErrorResponse, HealthResponse,
    PROTOCOL_VERSION,
};
use crate::renderer::{CapturedFrame, RenderError, Renderer};
use crate::validation::{RequestValidator, ValidationError};

#[derive(Clone)]
pub struct AppState {
    validator: RequestValidator,
    renderer: Arc<dyn Renderer>,
    render_lock: Arc<Mutex<()>>,
    requests: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
}

impl AppState {
    pub fn new(validator: RequestValidator, renderer: Arc<dyn Renderer>) -> Self {
        Self {
            validator,
            renderer,
            render_lock: Arc::new(Mutex::new(())),
            requests: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/captures/frame", post(capture_frame))
        .route("/v1/captures/frames", post(capture_frames))
        .route("/v1/captures/{request_id}", delete(cancel_capture))
        .with_state(state)
}

async fn health(State(state): State<AppState>) -> Json<HealthResponse<'static>> {
    let renderer_available = state.renderer.healthy().await;
    Json(HealthResponse {
        status: if renderer_available {
            "ready"
        } else {
            "unavailable"
        },
        protocol_version: PROTOCOL_VERSION,
        worker_version: env!("CARGO_PKG_VERSION"),
        renderer: state.renderer.name(),
        renderer_available,
        servo_version: state.renderer.servo_version(),
    })
}

async fn capture_frame(
    State(state): State<AppState>,
    Json(request): Json<CaptureRequest>,
) -> Result<Response, ApiError> {
    state.validator.validate(&request, false)?;
    if request.frames.len() != 1 {
        return Err(ApiError::bad_request(
            "invalid_frames",
            "single-frame capture requires exactly one frame",
        ));
    }

    let cancelled = register(&state, &request.request_id).await?;
    let images = render_registered(&state, &request, cancelled, None).await?;
    let Some(image) = images.into_iter().next() else {
        return Err(ApiError::internal(
            "invalid_renderer_response",
            "renderer returned no frame",
        ));
    };

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "image/png")
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::from(image))
        .expect("static response is valid"))
}

async fn capture_frames(
    State(state): State<AppState>,
    Json(request): Json<CaptureRequest>,
) -> Result<Response, ApiError> {
    state.validator.validate(&request, true)?;
    let output_dir = state
        .validator
        .output_dir(&request)
        .ok_or_else(|| ApiError::bad_request("invalid_output_dir", "output_dir is required"))?;
    let request_id = request.request_id.clone();
    tokio::fs::create_dir_all(&output_dir)
        .await
        .map_err(|error| {
            ApiError::internal(
                "output_write_failed",
                format!("could not create output_dir: {error}"),
            )
        })?;
    let cancelled = register(&state, &request_id).await?;
    let (line_tx, line_rx) = tokio::sync::mpsc::channel::<String>(16);
    tokio::spawn(run_batch(
        state, request, request_id, output_dir, cancelled, line_tx,
    ));
    let stream = ReceiverStream::new(line_rx).map(Ok::<_, Infallible>);
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/x-ndjson")
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::from_stream(stream))
        .expect("static response is valid"))
}

async fn cancel_capture(
    State(state): State<AppState>,
    Path(request_id): Path<String>,
) -> Result<Json<CancelResponse>, ApiError> {
    let requests = state.requests.lock().await;
    let Some(cancelled) = requests.get(&request_id) else {
        return Err(ApiError::not_found(
            "capture_not_found",
            "capture is not queued or active",
        ));
    };
    cancelled.store(true, Ordering::Release);
    Ok(Json(CancelResponse {
        request_id,
        status: "cancelling",
    }))
}

async fn register(state: &AppState, request_id: &str) -> Result<Arc<AtomicBool>, ApiError> {
    let cancelled = Arc::new(AtomicBool::new(false));
    let mut requests = state.requests.lock().await;
    if requests
        .insert(request_id.to_owned(), cancelled.clone())
        .is_some()
    {
        return Err(ApiError::conflict(
            "duplicate_request_id",
            "request_id is already queued or active",
        ));
    }
    Ok(cancelled)
}

async fn render_registered(
    state: &AppState,
    request: &CaptureRequest,
    cancelled: Arc<AtomicBool>,
    progress: Option<tokio::sync::mpsc::Sender<CapturedFrame>>,
) -> Result<Vec<bytes::Bytes>, ApiError> {
    let result = async {
        let _guard = state.render_lock.lock().await;
        if cancelled.load(Ordering::Acquire) {
            return Err(RenderError::Cancelled);
        }
        state.renderer.capture(request, cancelled, progress).await
    }
    .await;
    state.requests.lock().await.remove(&request.request_id);
    result.map_err(ApiError::from)
}

async fn run_batch(
    state: AppState,
    request: CaptureRequest,
    request_id: String,
    output_dir: PathBuf,
    cancelled: Arc<AtomicBool>,
    lines: tokio::sync::mpsc::Sender<String>,
) {
    let (frame_tx, mut frame_rx) = tokio::sync::mpsc::channel::<CapturedFrame>(2);
    let render_state = state.clone();
    let render_request = request.clone();
    let render = tokio::spawn(async move {
        render_registered(&render_state, &render_request, cancelled, Some(frame_tx)).await
    });
    let mut frames_written = 0usize;
    while let Some(frame) = frame_rx.recv().await {
        let path = output_dir.join(format!("frame-{:05}.png", frame.index));
        if let Err(error) = tokio::fs::write(&path, frame.png).await {
            let _ = send_batch_error(
                &lines,
                &request_id,
                "output_write_failed",
                &format!("could not write {}: {error}", path.display()),
            )
            .await;
            return;
        }
        frames_written += 1;
        let line = serde_json::json!({
            "request_id": request_id,
            "status": "progress",
            "captured": frames_written,
            "total": request.frames.len()
        });
        if lines.send(format!("{line}\n")).await.is_err() {
            return;
        }
    }

    match render.await {
        Ok(Ok(images))
            if images.len() == request.frames.len() && frames_written == images.len() =>
        {
            let complete = BatchResponse {
                request_id,
                status: "complete",
                output_dir: output_dir.to_string_lossy().into_owned(),
                frames_written,
            };
            if let Ok(line) = serde_json::to_string(&complete) {
                let _ = lines.send(format!("{line}\n")).await;
            }
        }
        Ok(Ok(_)) => {
            let _ = send_batch_error(
                &lines,
                &request_id,
                "invalid_renderer_response",
                "renderer returned the wrong number of frames",
            )
            .await;
        }
        Ok(Err(error)) => {
            let _ = send_batch_error(&lines, &request_id, error.code, &error.message).await;
        }
        Err(error) => {
            let _ = send_batch_error(
                &lines,
                &request_id,
                "render_task_failed",
                &error.to_string(),
            )
            .await;
        }
    }
}

async fn send_batch_error(
    lines: &tokio::sync::mpsc::Sender<String>,
    request_id: &str,
    code: &'static str,
    message: &str,
) -> Result<(), tokio::sync::mpsc::error::SendError<String>> {
    let line = serde_json::json!({
        "request_id": request_id,
        "status": "error",
        "error": { "code": code, "message": message }
    });
    lines.send(format!("{line}\n")).await
}

pub struct ApiError {
    status: StatusCode,
    code: &'static str,
    message: String,
}

impl ApiError {
    fn bad_request(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, code, message)
    }

    fn not_found(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::NOT_FOUND, code, message)
    }

    fn conflict(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::CONFLICT, code, message)
    }

    fn internal(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::INTERNAL_SERVER_ERROR, code, message)
    }

    fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
        }
    }
}

impl From<ValidationError> for ApiError {
    fn from(error: ValidationError) -> Self {
        Self::bad_request("invalid_capture_request", error.to_string())
    }
}

impl From<RenderError> for ApiError {
    fn from(error: RenderError) -> Self {
        match error {
            RenderError::Unavailable(message) => {
                Self::new(StatusCode::NOT_IMPLEMENTED, "renderer_unavailable", message)
            }
            RenderError::Cancelled => Self::new(
                StatusCode::CONFLICT,
                "capture_cancelled",
                "capture was cancelled",
            ),
            RenderError::ReadinessTimeout => Self::new(
                StatusCode::GATEWAY_TIMEOUT,
                "readiness_timeout",
                error.to_string(),
            ),
            RenderError::Player(_) | RenderError::Manifest(_) => Self::new(
                StatusCode::UNPROCESSABLE_ENTITY,
                "invalid_player",
                error.to_string(),
            ),
            RenderError::Failed(_) => {
                Self::new(StatusCode::BAD_GATEWAY, "render_failed", error.to_string())
            }
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (
            self.status,
            Json(ErrorResponse {
                error: ErrorBody {
                    code: self.code,
                    message: self.message,
                },
            }),
        )
            .into_response()
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::AtomicBool;
    use std::time::{SystemTime, UNIX_EPOCH};

    use async_trait::async_trait;
    use axum::body::Body;
    use bytes::Bytes;
    use http::{Request, StatusCode};
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    use super::*;
    use crate::renderer::{CapturedFrame, UnavailableRenderer};
    use crate::validation::Limits;

    fn app() -> Router {
        let validator = RequestValidator::new(
            ["http://127.0.0.1:3000".into()],
            PathBuf::from("/tmp/animate-it-servo-tests"),
            Limits::default(),
        )
        .unwrap();
        router(AppState::new(validator, Arc::new(UnavailableRenderer)))
    }

    struct FakeRenderer;

    #[async_trait]
    impl Renderer for FakeRenderer {
        fn name(&self) -> &'static str {
            "fake"
        }

        fn available(&self) -> bool {
            true
        }

        fn servo_version(&self) -> Option<&'static str> {
            Some("test")
        }

        async fn capture(
            &self,
            request: &CaptureRequest,
            _cancelled: Arc<AtomicBool>,
            progress: Option<tokio::sync::mpsc::Sender<CapturedFrame>>,
        ) -> Result<Vec<Bytes>, RenderError> {
            let mut images = Vec::new();
            for index in 0..request.frames.len() {
                let png = Bytes::from_static(b"test-png");
                if let Some(progress) = &progress {
                    progress
                        .send(CapturedFrame {
                            index,
                            png: png.clone(),
                        })
                        .await
                        .unwrap();
                }
                images.push(png);
            }
            Ok(images)
        }
    }

    struct CancellableRenderer;

    #[async_trait]
    impl Renderer for CancellableRenderer {
        fn name(&self) -> &'static str {
            "cancellable-fake"
        }

        fn available(&self) -> bool {
            true
        }

        fn servo_version(&self) -> Option<&'static str> {
            Some("test")
        }

        async fn capture(
            &self,
            _request: &CaptureRequest,
            cancelled: Arc<AtomicBool>,
            _progress: Option<tokio::sync::mpsc::Sender<CapturedFrame>>,
        ) -> Result<Vec<Bytes>, RenderError> {
            while !cancelled.load(Ordering::Acquire) {
                tokio::time::sleep(std::time::Duration::from_millis(1)).await;
            }
            Err(RenderError::Cancelled)
        }
    }

    fn capture_json() -> serde_json::Value {
        serde_json::json!({
            "request_id": "request-1",
            "url": "http://127.0.0.1:3000/motion/internal/render_pages/ticket-1",
            "composition": "profile-card",
            "width": 1200,
            "height": 630,
            "duration": 60,
            "manifest_version": 1,
            "frames": [0],
            "transparency": true,
            "ready_timeout_ms": 30000
        })
    }

    #[tokio::test]
    async fn health_discloses_unavailable_renderer() {
        let response = app()
            .oneshot(Request::get("/v1/health").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = response.into_body().collect().await.unwrap().to_bytes();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["renderer_available"], false);
        assert_eq!(json["status"], "unavailable");
    }

    #[tokio::test]
    async fn valid_capture_returns_explicit_not_implemented() {
        let response = app()
            .oneshot(
                Request::post("/v1/captures/frame")
                    .header("content-type", "application/json")
                    .body(Body::from(capture_json().to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NOT_IMPLEMENTED);
        let body = response.into_body().collect().await.unwrap().to_bytes();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "renderer_unavailable");
    }

    #[tokio::test]
    async fn rejects_external_url_before_renderer() {
        let mut request = capture_json();
        request["url"] = "https://example.com/motion/internal/render_pages/ticket".into();
        let response = app()
            .oneshot(
                Request::post("/v1/captures/frame")
                    .header("content-type", "application/json")
                    .body(Body::from(request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn batch_requires_output_directory() {
        let response = app()
            .oneshot(
                Request::post("/v1/captures/frames")
                    .header("content-type", "application/json")
                    .body(Body::from(capture_json().to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn batch_streams_progress_after_writing_each_frame() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("animate-it-servo-{suffix}"));
        std::fs::create_dir_all(&root).unwrap();
        let output = root.join("capture");
        let validator = RequestValidator::new(
            ["http://127.0.0.1:3000".into()],
            root.clone(),
            Limits::default(),
        )
        .unwrap();
        let app = router(AppState::new(validator, Arc::new(FakeRenderer)));
        let mut request = capture_json();
        request["frames"] = serde_json::json!([0, 1]);
        request["output_dir"] = output.to_string_lossy().into_owned().into();

        let response = app
            .oneshot(
                Request::post("/v1/captures/frames")
                    .header("content-type", "application/json")
                    .body(Body::from(request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = response.into_body().collect().await.unwrap().to_bytes();
        let lines = std::str::from_utf8(&body)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0]["status"], "progress");
        assert_eq!(lines[0]["captured"], 1);
        assert_eq!(lines[1]["captured"], 2);
        assert_eq!(lines[2]["status"], "complete");
        assert_eq!(
            std::fs::read(output.join("frame-00000.png")).unwrap(),
            b"test-png"
        );
        assert_eq!(
            std::fs::read(output.join("frame-00001.png")).unwrap(),
            b"test-png"
        );
        std::fs::remove_dir_all(root).unwrap();
    }

    #[tokio::test]
    async fn delete_cancels_an_active_streamed_batch() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("animate-it-servo-cancel-{suffix}"));
        std::fs::create_dir_all(&root).unwrap();
        let validator = RequestValidator::new(
            ["http://127.0.0.1:3000".into()],
            root.clone(),
            Limits::default(),
        )
        .unwrap();
        let app = router(AppState::new(validator, Arc::new(CancellableRenderer)));
        let mut request = capture_json();
        request["output_dir"] = root.join("capture").to_string_lossy().into_owned().into();

        let batch = app
            .clone()
            .oneshot(
                Request::post("/v1/captures/frames")
                    .header("content-type", "application/json")
                    .body(Body::from(request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(batch.status(), StatusCode::OK);

        let cancellation = app
            .oneshot(
                Request::delete("/v1/captures/request-1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(cancellation.status(), StatusCode::OK);

        let body = batch.into_body().collect().await.unwrap().to_bytes();
        let final_line: serde_json::Value = serde_json::from_slice(
            std::str::from_utf8(&body)
                .unwrap()
                .lines()
                .last()
                .unwrap()
                .as_bytes(),
        )
        .unwrap();
        assert_eq!(final_line["status"], "error");
        assert_eq!(final_line["error"]["code"], "capture_cancelled");
        std::fs::remove_dir_all(root).unwrap();
    }
}
