use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::PathBuf;
use std::sync::Arc;

use animate_it_servo::renderer::{Renderer, UnavailableRenderer, WebDriverRenderer};
use animate_it_servo::server::{AppState, router};
use animate_it_servo::validation::{Limits, RequestValidator};
use clap::Parser;
use tracing_subscriber::EnvFilter;

#[derive(Debug, Parser)]
#[command(version, about)]
struct Args {
    #[arg(long, env = "ANIMATE_IT_SERVO_PORT", default_value_t = 4178)]
    port: u16,
    #[arg(
        long,
        env = "ANIMATE_IT_SERVO_ALLOWED_ORIGINS",
        value_delimiter = ',',
        default_value = "http://127.0.0.1:3000"
    )]
    allowed_origins: Vec<String>,
    #[arg(
        long,
        env = "ANIMATE_IT_SERVO_CAPTURE_ROOT",
        default_value = "/tmp/animate-it-servo"
    )]
    capture_root: PathBuf,
    #[arg(long, env = "ANIMATE_IT_SERVO_WEBDRIVER_URL")]
    webdriver_url: Option<String>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let args = Args::parse();
    let validator =
        RequestValidator::new(args.allowed_origins, args.capture_root, Limits::default())?;
    let renderer: Arc<dyn Renderer> = match args.webdriver_url {
        Some(endpoint) => Arc::new(WebDriverRenderer::new(endpoint)?),
        None => Arc::new(UnavailableRenderer),
    };
    let app = router(AppState::new(validator, renderer));
    let address = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), args.port);
    let listener = tokio::net::TcpListener::bind(address).await?;
    tracing::info!(%address, "AnimateIt Servo protocol worker listening");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
}
