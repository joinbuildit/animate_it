use std::path::{Component, Path, PathBuf};

use thiserror::Error;
use url::{Origin, Url};

use crate::protocol::{CaptureRequest, PLAYER_MANIFEST_VERSION, PlayerManifest};

const MAX_REQUEST_ID_LEN: usize = 128;
const MAX_COMPOSITION_LEN: usize = 200;

#[derive(Clone, Debug)]
pub struct Limits {
    pub max_width: u32,
    pub max_height: u32,
    pub max_pixels: u64,
    pub max_frames: usize,
    pub max_frame: u32,
    pub min_timeout_ms: u64,
    pub max_timeout_ms: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_width: 4096,
            max_height: 4096,
            max_pixels: 16_777_216,
            max_frames: 10_000,
            max_frame: 1_000_000,
            min_timeout_ms: 100,
            max_timeout_ms: 120_000,
        }
    }
}

#[derive(Debug, Error, PartialEq)]
pub enum ValidationError {
    #[error("request_id must contain 1 to {MAX_REQUEST_ID_LEN} URL-safe characters")]
    RequestId,
    #[error("composition must contain 1 to {MAX_COMPOSITION_LEN} safe characters")]
    Composition,
    #[error("URL must use http or https")]
    Scheme,
    #[error("URL contains credentials")]
    Credentials,
    #[error("URL origin is not allowed")]
    Origin,
    #[error("URL path is not an AnimateIt internal render page")]
    RenderPath,
    #[error("width and height must be non-zero and within configured limits")]
    Dimensions,
    #[error("frames must be non-empty and within configured limits")]
    Frames,
    #[error("ready_timeout_ms is outside configured limits")]
    Timeout,
    #[error("batch capture requires output_dir")]
    MissingOutputDirectory,
    #[error("output_dir must be an absolute, traversal-free path inside the capture root")]
    OutputDirectory,
    #[error("player manifest does not match the capture request: {0}")]
    Manifest(&'static str),
    #[error("invalid URL: {0}")]
    InvalidUrl(String),
}

#[derive(Clone, Debug)]
pub struct RequestValidator {
    allowed_origins: Vec<Origin>,
    capture_root: PathBuf,
    limits: Limits,
}

impl RequestValidator {
    pub fn new(
        allowed_origins: impl IntoIterator<Item = String>,
        capture_root: PathBuf,
        limits: Limits,
    ) -> Result<Self, ValidationError> {
        let allowed_origins = allowed_origins
            .into_iter()
            .map(|origin| {
                Url::parse(&origin)
                    .map(|url| url.origin())
                    .map_err(|error| ValidationError::InvalidUrl(error.to_string()))
            })
            .collect::<Result<Vec<_>, _>>()?;

        if allowed_origins.is_empty() || !capture_root.is_absolute() {
            return Err(ValidationError::Origin);
        }

        Ok(Self {
            allowed_origins,
            capture_root: normalize_absolute(&capture_root)
                .ok_or(ValidationError::OutputDirectory)?,
            limits,
        })
    }

    pub fn validate(&self, request: &CaptureRequest, batch: bool) -> Result<Url, ValidationError> {
        if !is_safe_token(&request.request_id, MAX_REQUEST_ID_LEN) {
            return Err(ValidationError::RequestId);
        }
        if !is_safe_token(&request.composition, MAX_COMPOSITION_LEN) {
            return Err(ValidationError::Composition);
        }

        let url = Url::parse(&request.url)
            .map_err(|error| ValidationError::InvalidUrl(error.to_string()))?;
        if !matches!(url.scheme(), "http" | "https") {
            return Err(ValidationError::Scheme);
        }
        if !url.username().is_empty() || url.password().is_some() {
            return Err(ValidationError::Credentials);
        }
        if !self.allowed_origins.contains(&url.origin()) {
            return Err(ValidationError::Origin);
        }
        if !is_render_path(url.path(), &request.composition) {
            return Err(ValidationError::RenderPath);
        }

        let pixels = u64::from(request.width) * u64::from(request.height);
        if request.width == 0
            || request.height == 0
            || request.width > self.limits.max_width
            || request.height > self.limits.max_height
            || pixels > self.limits.max_pixels
        {
            return Err(ValidationError::Dimensions);
        }
        if request.frames.is_empty()
            || request.frames.len() > self.limits.max_frames
            || request.duration == 0
            || request.manifest_version != PLAYER_MANIFEST_VERSION
            || request
                .frames
                .iter()
                .any(|frame| *frame > self.limits.max_frame || *frame >= request.duration)
        {
            return Err(ValidationError::Frames);
        }
        if !(self.limits.min_timeout_ms..=self.limits.max_timeout_ms)
            .contains(&request.ready_timeout_ms)
        {
            return Err(ValidationError::Timeout);
        }

        match (&request.output_dir, batch) {
            (None, true) => return Err(ValidationError::MissingOutputDirectory),
            (Some(path), _) => {
                let path =
                    normalize_absolute(Path::new(path)).ok_or(ValidationError::OutputDirectory)?;
                if path == self.capture_root || !path.starts_with(&self.capture_root) {
                    return Err(ValidationError::OutputDirectory);
                }
            }
            (None, false) => {}
        }

        Ok(url)
    }

    pub fn validate_manifest(
        &self,
        request: &CaptureRequest,
        manifest: &PlayerManifest,
    ) -> Result<(), ValidationError> {
        validate_manifest(request, manifest)
    }

    pub fn output_dir(&self, request: &CaptureRequest) -> Option<PathBuf> {
        request
            .output_dir
            .as_deref()
            .and_then(|path| normalize_absolute(Path::new(path)))
    }
}

pub fn validate_manifest(
    request: &CaptureRequest,
    manifest: &PlayerManifest,
) -> Result<(), ValidationError> {
    if manifest.version != PLAYER_MANIFEST_VERSION {
        return Err(ValidationError::Manifest("unsupported version"));
    }
    if manifest.id != request.composition {
        return Err(ValidationError::Manifest("composition id"));
    }
    if manifest.width != request.width || manifest.height != request.height {
        return Err(ValidationError::Manifest("dimensions"));
    }
    if manifest.duration == 0
        || request
            .frames
            .iter()
            .any(|frame| *frame >= manifest.duration)
    {
        return Err(ValidationError::Manifest("frame range"));
    }
    Ok(())
}

fn is_safe_token(value: &str, max_len: usize) -> bool {
    !value.is_empty()
        && value.len() <= max_len
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
}

fn is_render_path(path: &str, composition: &str) -> bool {
    let segments = path
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect::<Vec<_>>();
    let internal = segments
        .iter()
        .position(|segment| *segment == "internal")
        .is_some_and(|internal_index| {
            matches!(
                segments.get(internal_index + 1..),
                Some(["render_pages", token]) if is_safe_token(token, MAX_REQUEST_ID_LEN)
            )
        });
    let player = segments
        .iter()
        .position(|segment| *segment == "compositions")
        .is_some_and(
            |index| matches!(segments.get(index + 1..), Some([id, "player"]) if *id == composition),
        );
    internal || player
}

fn normalize_absolute(path: &Path) -> Option<PathBuf> {
    if !path.is_absolute() {
        return None;
    }
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(prefix) => normalized.push(prefix.as_os_str()),
            Component::RootDir => normalized.push(component.as_os_str()),
            Component::Normal(part) => normalized.push(part),
            Component::CurDir | Component::ParentDir => return None,
        }
    }
    Some(normalized)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request() -> CaptureRequest {
        CaptureRequest {
            request_id: "request-1".into(),
            url: "http://127.0.0.1:3000/motion/internal/render_pages/ticket-1".into(),
            composition: "profile-card".into(),
            width: 1200,
            height: 630,
            duration: 10,
            manifest_version: 1,
            frames: vec![0, 5],
            transparency: true,
            ready_timeout_ms: 30_000,
            output_dir: None,
        }
    }

    fn validator() -> RequestValidator {
        RequestValidator::new(
            ["http://127.0.0.1:3000".into()],
            PathBuf::from("/tmp/animate-it-servo"),
            Limits::default(),
        )
        .unwrap()
    }

    #[test]
    fn accepts_internal_render_page() {
        assert!(validator().validate(&request(), false).is_ok());
    }

    #[test]
    fn accepts_only_the_requested_compositions_player() {
        let mut request = request();
        request.url =
            "http://127.0.0.1:3000/motion/compositions/profile-card/player?props_json=%7B%7D"
                .into();
        assert!(validator().validate(&request, false).is_ok());

        request.url = "http://127.0.0.1:3000/motion/compositions/other/player".into();
        assert_eq!(
            validator().validate(&request, false),
            Err(ValidationError::RenderPath)
        );

        request.url = "http://127.0.0.1:3000/motion/compositions/profile-card/filmstrip".into();
        assert_eq!(
            validator().validate(&request, false),
            Err(ValidationError::RenderPath)
        );
    }

    #[test]
    fn rejects_file_and_unlisted_origins() {
        let mut request = request();
        request.url = "file:///etc/passwd".into();
        assert_eq!(
            validator().validate(&request, false),
            Err(ValidationError::Scheme)
        );

        request.url = "http://localhost:3000/motion/internal/render_pages/ticket".into();
        assert_eq!(
            validator().validate(&request, false),
            Err(ValidationError::Origin)
        );
    }

    #[test]
    fn rejects_public_and_traversal_paths() {
        let mut request = request();
        request.url = "http://127.0.0.1:3000/motion/compositions/demo/player".into();
        assert_eq!(
            validator().validate(&request, false),
            Err(ValidationError::RenderPath)
        );

        request.url = "http://127.0.0.1:3000/motion/internal/render_pages/ticket-1".into();
        request.output_dir = Some("/tmp/animate-it-servo/../escaped".into());
        assert_eq!(
            validator().validate(&request, true),
            Err(ValidationError::OutputDirectory)
        );
    }

    #[test]
    fn validates_manifest_identity_dimensions_and_frames() {
        let request = request();
        let manifest = PlayerManifest {
            version: 1,
            id: "profile-card".into(),
            width: 1200,
            height: 630,
            duration: 10,
        };
        assert!(validator().validate_manifest(&request, &manifest).is_ok());

        let mut wrong = manifest;
        wrong.duration = 5;
        assert_eq!(
            validator().validate_manifest(&request, &wrong),
            Err(ValidationError::Manifest("frame range"))
        );
    }
}
