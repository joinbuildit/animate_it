# AnimateIt Servo worker

This directory contains the optional, localhost-only rendering worker protocol for AnimateIt.
The HTTP server and its validation are implemented and tested. It can drive a prestarted Servo
`servoshell` via WebDriver. Without a configured WebDriver endpoint, it deliberately reports
`renderer_available: false` and returns `501 renderer_unavailable`; it does not fabricate images
or silently use another browser.

## Run

```sh
cargo run -- \
  --allowed-origins http://127.0.0.1:3000 \
  --capture-root /absolute/path/to/rails/tmp/animate_it \
  --webdriver-url http://127.0.0.1:7000
```

The listener is always bound to `127.0.0.1`; there is no option to expose it publicly.

Endpoints:

- `GET /v1/health`
- `POST /v1/captures/frame` — returns `image/png` when a renderer is available
- `POST /v1/captures/frames` — writes `frame-%05d.png` beneath the configured capture root
- `DELETE /v1/captures/:request_id` — cancels queued or active work

Requests are validated before reaching a renderer. Only configured HTTP(S) origins and paths of
the form `.../internal/render_pages/:opaque_ticket` are accepted for private images. Video capture
also permits the exact `.../compositions/:requested_id/player` path. Credentials, file URLs,
unbounded dimensions/frame counts/timeouts, traversal, and batch output outside the capture root
are rejected. A process-wide mutex serializes capture calls; cancellation remains responsive while
a request is queued or active.

## Servo engine adapter

Servo 0.4.0 is the current crates.io release. Its public API includes `ServoBuilder`,
`SoftwareRenderingContext`, `WebViewBuilder`, `WebView::evaluate_javascript`, and
`WebView::take_screenshot`. Those objects are intentionally thread-bound. A correct server adapter
therefore needs a dedicated engine thread that owns Servo, its software rendering context, and its
event-loop pumping for the lifetime of the process. Compiling the HTTP server against Servo without
that lifecycle would compile code but would not establish reliable rendering.

The worker therefore drives the official `servoshell` binary, which already owns that lifecycle
and supports `--headless --webdriver PORT --window-size WxH`. Start it separately, for example:

```sh
servoshell --headless --webdriver 7000 --window-size 1200x630 about:blank
```

Set `ANIMATE_IT_SERVO_WEBDRIVER_URL=http://127.0.0.1:7000`. The adapter creates a fresh session,
sets its viewport, navigates, polls AnimateIt's readiness/error markers, validates the embedded
manifest, calls `setFrame`, obtains real PNG screenshots, and closes the session.

The integration has been exercised with the official Servo 0.4.0 macOS `servoshell`: health
reported ready, a 240×120 RGBA PNG was captured, and a three-frame batch wrote all PNGs while
streaming NDJSON progress. Servo remains pre-1.0, so pin the tested 0.4.0 binary and checksum in
deployment packaging rather than silently tracking newer releases.

Remaining production-hardening work:

1. Pin a Servo/servoshell release and checksum in packaging; optionally add supervised child
   process startup via `ANIMATE_IT_SERVO_SHELL_PATH`.
2. Add a servoshell-level resource interception policy
   before claiming subresource-origin enforcement; main-document validation alone is insufficient.
3. Terminate and restart the child after timeouts or protocol corruption. Never fall back inside
   this worker; the Ruby `:auto` backend owns Playwright fallback.

An in-process adapter can later replace this without changing the HTTP API because engine access is
isolated behind `Renderer`.
