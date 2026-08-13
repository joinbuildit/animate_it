use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u32 = 1;
pub const PLAYER_MANIFEST_VERSION: u32 = 1;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CaptureRequest {
    pub request_id: String,
    pub url: String,
    pub composition: String,
    pub width: u32,
    pub height: u32,
    pub duration: u32,
    pub manifest_version: u32,
    pub frames: Vec<u32>,
    #[serde(default = "default_true")]
    pub transparency: bool,
    #[serde(default = "default_ready_timeout")]
    pub ready_timeout_ms: u64,
    #[serde(default)]
    pub output_dir: Option<String>,
}

fn default_true() -> bool {
    true
}

fn default_ready_timeout() -> u64 {
    30_000
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct PlayerManifest {
    pub version: u32,
    pub id: String,
    pub width: u32,
    pub height: u32,
    pub duration: u32,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse<'a> {
    pub status: &'a str,
    pub protocol_version: u32,
    pub worker_version: &'a str,
    pub renderer: &'a str,
    pub renderer_available: bool,
    pub servo_version: Option<&'a str>,
}

#[derive(Debug, Serialize)]
pub struct BatchResponse {
    pub request_id: String,
    pub status: &'static str,
    pub output_dir: String,
    pub frames_written: usize,
}

#[derive(Debug, Serialize)]
pub struct CancelResponse {
    pub request_id: String,
    pub status: &'static str,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: ErrorBody,
}

#[derive(Debug, Serialize)]
pub struct ErrorBody {
    pub code: &'static str,
    pub message: String,
}
