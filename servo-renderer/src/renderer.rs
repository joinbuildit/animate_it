use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use async_trait::async_trait;
use base64::Engine;
use bytes::Bytes;
use reqwest::Client;
use serde_json::{Value, json};
use thiserror::Error;
use tokio::sync::mpsc;
use tokio::time::{Duration, Instant, sleep};
use url::Url;

use crate::protocol::{CaptureRequest, PlayerManifest};
use crate::validation::validate_manifest;

#[derive(Debug, Error)]
pub enum RenderError {
    #[error("Servo renderer is unavailable: {0}")]
    Unavailable(String),
    #[error("capture was cancelled")]
    Cancelled,
    #[error("player readiness timed out")]
    ReadinessTimeout,
    #[error("player reported an error: {0}")]
    Player(String),
    #[error("player manifest is invalid: {0}")]
    Manifest(String),
    #[error("render failed: {0}")]
    Failed(String),
}

#[derive(Debug)]
pub struct CapturedFrame {
    pub index: usize,
    pub png: Bytes,
}

#[async_trait]
pub trait Renderer: Send + Sync + 'static {
    fn name(&self) -> &'static str;
    fn available(&self) -> bool;
    fn servo_version(&self) -> Option<&'static str>;
    async fn healthy(&self) -> bool {
        self.available()
    }

    async fn capture(
        &self,
        request: &CaptureRequest,
        cancelled: Arc<AtomicBool>,
        frames: Option<mpsc::Sender<CapturedFrame>>,
    ) -> Result<Vec<Bytes>, RenderError>;
}

/// Honest placeholder for the HTTP integration when Servo support is not compiled in.
/// It never returns fabricated image data.
pub struct UnavailableRenderer;

#[async_trait]
impl Renderer for UnavailableRenderer {
    fn name(&self) -> &'static str {
        "servo"
    }

    fn available(&self) -> bool {
        false
    }

    fn servo_version(&self) -> Option<&'static str> {
        None
    }

    async fn capture(
        &self,
        _request: &CaptureRequest,
        _cancelled: Arc<AtomicBool>,
        _frames: Option<mpsc::Sender<CapturedFrame>>,
    ) -> Result<Vec<Bytes>, RenderError> {
        Err(RenderError::Unavailable(
            "this build contains the protocol server but no Servo engine adapter".into(),
        ))
    }
}

/// Drives a prestarted Servo `servoshell` through its W3C WebDriver endpoint.
/// Start Servo with `servoshell --headless --webdriver PORT --window-size WxH about:blank`.
pub struct WebDriverRenderer {
    endpoint: String,
    client: Client,
}

impl WebDriverRenderer {
    pub fn new(endpoint: impl Into<String>) -> Result<Self, RenderError> {
        let endpoint = endpoint.into().trim_end_matches('/').to_owned();
        let parsed = Url::parse(&endpoint)
            .map_err(|error| RenderError::Unavailable(format!("invalid WebDriver URL: {error}")))?;
        if parsed.scheme() != "http" || !parsed.username().is_empty() || parsed.password().is_some()
        {
            return Err(RenderError::Unavailable(
                "WebDriver URL must be an unauthenticated loopback http URL".into(),
            ));
        }
        if !parsed
            .host_str()
            .is_some_and(|host| matches!(host, "127.0.0.1" | "localhost" | "::1"))
        {
            return Err(RenderError::Unavailable(
                "WebDriver URL must use a loopback host".into(),
            ));
        }
        Ok(Self {
            endpoint,
            client: Client::builder()
                .timeout(Duration::from_secs(10))
                .build()
                .map_err(|error| RenderError::Unavailable(error.to_string()))?,
        })
    }

    async fn command(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, RenderError> {
        let mut request = self
            .client
            .request(method, format!("{}{path}", self.endpoint));
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request
            .send()
            .await
            .map_err(|error| RenderError::Failed(format!("WebDriver request failed: {error}")))?;
        let status = response.status();
        let payload: Value = response
            .json()
            .await
            .map_err(|error| RenderError::Failed(format!("invalid WebDriver response: {error}")))?;
        if !status.is_success() {
            let message = payload
                .pointer("/value/message")
                .and_then(Value::as_str)
                .unwrap_or("WebDriver command failed");
            return Err(RenderError::Failed(format!("{status}: {message}")));
        }
        Ok(payload.get("value").cloned().unwrap_or(payload))
    }

    async fn create_session(&self, request: &CaptureRequest) -> Result<String, RenderError> {
        let payload = self
            .command(
                reqwest::Method::POST,
                "/session",
                Some(json!({ "capabilities": { "alwaysMatch": {} } })),
            )
            .await?;
        let session_id = payload
            .get("sessionId")
            .and_then(Value::as_str)
            .or_else(|| payload.as_str())
            .ok_or_else(|| RenderError::Failed("WebDriver omitted sessionId".into()))?
            .to_owned();
        self.command(
            reqwest::Method::POST,
            &format!("/session/{session_id}/window/rect"),
            Some(json!({ "x": 0, "y": 0, "width": request.width, "height": request.height })),
        )
        .await?;
        Ok(session_id)
    }

    async fn execute(
        &self,
        session_id: &str,
        script: &str,
        args: Value,
    ) -> Result<Value, RenderError> {
        self.command(
            reqwest::Method::POST,
            &format!("/session/{session_id}/execute/sync"),
            Some(json!({ "script": script, "args": args })),
        )
        .await
    }

    async fn wait_until_ready(
        &self,
        session_id: &str,
        request: &CaptureRequest,
        cancelled: &AtomicBool,
    ) -> Result<(), RenderError> {
        let deadline = Instant::now() + Duration::from_millis(request.ready_timeout_ms);
        loop {
            if cancelled.load(std::sync::atomic::Ordering::Acquire) {
                return Err(RenderError::Cancelled);
            }
            let state = self
                .execute(
                    session_id,
                    r#"return (function () {
                      var root = document.documentElement;
                      var manifest = document.querySelector('script[data-animate-it-manifest]');
                      return {
                        ready: root && root.dataset.animateItReady === '1',
                        error: root && root.dataset.animateItError || null,
                        manifest: manifest && manifest.textContent || null,
                        url: location.href
                      };
                    }());"#,
                    json!([]),
                )
                .await?;

            if let Some(error) = state.get("error").and_then(Value::as_str)
                && !error.is_empty()
            {
                return Err(RenderError::Player(error.to_owned()));
            }
            if state.get("ready").and_then(Value::as_bool) == Some(true) {
                let final_url = state
                    .get("url")
                    .and_then(Value::as_str)
                    .ok_or_else(|| RenderError::Player("player URL is missing".into()))?;
                let initial = Url::parse(&request.url)
                    .map_err(|error| RenderError::Player(error.to_string()))?;
                let final_url = Url::parse(final_url)
                    .map_err(|error| RenderError::Player(error.to_string()))?;
                if initial.origin() != final_url.origin() {
                    return Err(RenderError::Player(
                        "navigation left the allowed origin".into(),
                    ));
                }
                let manifest: PlayerManifest = serde_json::from_str(
                    state
                        .get("manifest")
                        .and_then(Value::as_str)
                        .ok_or_else(|| RenderError::Manifest("manifest is missing".into()))?,
                )
                .map_err(|error| RenderError::Manifest(error.to_string()))?;
                validate_manifest(request, &manifest)
                    .map_err(|error| RenderError::Manifest(error.to_string()))?;
                return Ok(());
            }
            if Instant::now() >= deadline {
                return Err(RenderError::ReadinessTimeout);
            }
            sleep(Duration::from_millis(25)).await;
        }
    }

    async fn screenshot(
        &self,
        session_id: &str,
        request: &CaptureRequest,
    ) -> Result<Bytes, RenderError> {
        let encoded = self
            .command(
                reqwest::Method::GET,
                &format!("/session/{session_id}/screenshot"),
                None,
            )
            .await?
            .as_str()
            .ok_or_else(|| RenderError::Failed("WebDriver screenshot was not base64".into()))?
            .to_owned();
        let png = base64::engine::general_purpose::STANDARD
            .decode(encoded)
            .map_err(|error| RenderError::Failed(format!("invalid screenshot base64: {error}")))?;
        if !png.starts_with(b"\x89PNG\r\n\x1a\n") {
            return Err(RenderError::Failed(
                "WebDriver screenshot was not a PNG".into(),
            ));
        }
        if png.len() < 26 || &png[12..16] != b"IHDR" {
            return Err(RenderError::Failed("PNG has no valid IHDR".into()));
        }
        let width = u32::from_be_bytes(png[16..20].try_into().expect("checked PNG length"));
        let height = u32::from_be_bytes(png[20..24].try_into().expect("checked PNG length"));
        if width != request.width || height != request.height {
            return Err(RenderError::Failed(format!(
                "screenshot dimensions were {width}x{height}, expected {}x{}",
                request.width, request.height
            )));
        }
        if request.transparency && !matches!(png[25], 4 | 6) {
            return Err(RenderError::Failed(
                "screenshot PNG does not contain an alpha channel".into(),
            ));
        }
        Ok(Bytes::from(png))
    }

    async fn close_session(&self, session_id: &str) {
        let _ = self
            .command(
                reqwest::Method::DELETE,
                &format!("/session/{session_id}"),
                None,
            )
            .await;
    }
}

#[async_trait]
impl Renderer for WebDriverRenderer {
    fn name(&self) -> &'static str {
        "servo-webdriver"
    }

    fn available(&self) -> bool {
        true
    }

    fn servo_version(&self) -> Option<&'static str> {
        Some("0.4.0")
    }

    async fn healthy(&self) -> bool {
        matches!(
            tokio::time::timeout(
                Duration::from_millis(750),
                self.command(reqwest::Method::GET, "/status", None)
            )
            .await,
            Ok(Ok(_))
        )
    }

    async fn capture(
        &self,
        request: &CaptureRequest,
        cancelled: Arc<AtomicBool>,
        progress: Option<mpsc::Sender<CapturedFrame>>,
    ) -> Result<Vec<Bytes>, RenderError> {
        let session_id = self.create_session(request).await?;
        let result = async {
            self.command(
                reqwest::Method::POST,
                &format!("/session/{session_id}/url"),
                Some(json!({ "url": request.url })),
            )
            .await?;
            self.wait_until_ready(&session_id, request, &cancelled)
                .await?;

            let mut frames = Vec::with_capacity(request.frames.len());
            for (index, frame) in request.frames.iter().enumerate() {
                if cancelled.load(std::sync::atomic::Ordering::Acquire) {
                    return Err(RenderError::Cancelled);
                }
                self.execute(
                    &session_id,
                    "return window.__animateIt.setFrame(arguments[0]);",
                    json!([frame]),
                )
                .await?;
                let png = self.screenshot(&session_id, request).await?;
                if let Some(progress) = &progress {
                    progress
                        .send(CapturedFrame {
                            index,
                            png: png.clone(),
                        })
                        .await
                        .map_err(|_| RenderError::Cancelled)?;
                }
                frames.push(png);
            }
            Ok(frames)
        }
        .await;
        self.close_session(&session_id).await;
        result
    }
}

#[cfg(test)]
mod webdriver_tests {
    use super::*;

    #[test]
    fn only_accepts_loopback_http_endpoints() {
        assert!(WebDriverRenderer::new("http://127.0.0.1:7000").is_ok());
        assert!(WebDriverRenderer::new("http://localhost:7000/wd").is_ok());
        assert!(WebDriverRenderer::new("https://127.0.0.1:7000").is_err());
        assert!(WebDriverRenderer::new("http://example.com:7000").is_err());
        assert!(WebDriverRenderer::new("http://user:pass@127.0.0.1:7000").is_err());
    }
}
