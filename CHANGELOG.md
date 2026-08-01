# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-08-01

### Added
- Declarative schema-v2 track recording for sampled CSS variables, dynamic
  text, word reveals, and compact keyframe tracks.
- Browser-driven `/player` playback and export. Client-driven compositions
  render once per structural layer and seek deterministically without a Rails
  request for every frame.
- `client_driven!`, `structure_epochs`, `track_vars`, `text_track`,
  `verification_props`, and deterministic native CSS/Web Animation seeking.
- Secure production frontend playback with explicit `public_player!`
  allowlisting, a responsive `animate_it_player` iframe helper, autonomous
  Play/Pause/loop transport, and synchronized byte-range audio.
- Player-versus-filmstrip verification with RGB and alpha comparison, props
  matrices, structural-boundary sampling, and an every-frame `verify_all` gate.
- Checksum and provenance preflight for host-owned composition source assets.

### Changed
- Studio playback and seeking use the same client runtime as export for
  client-driven compositions.
- Animated outputs preserve declared audio trim, loop, gain, and partial-range
  alignment; GIF and PNG outputs remain silent.
- PNG sequences are published to their declared destination directory.
- Declared outputs covering the same frame range now share one browser capture
  instead of repeating every screenshot for each output format.
- Removed the no-op Studio render-concurrency settings; capture remains
  sequential so ordering, progress, and cancellation are deterministic.

### Compatibility
- Continued support for Ruby >= 3.3, Rails >= 7.2, HAML >= 6.3, HAML and ERB
  sidecars, the packaged renderer executable, configurable mount paths and host
  stylesheets, and the Rails 7.2 / Rails 8.1 appraisal matrix.

## [0.3.2] - 2026-07-23

### Fixed
- Studio audio is now served with HTTP byte-range support (Accept-Ranges,
  206 Partial Content). Browsers refuse to seek media served without it, so
  play-pause-play and scrub-then-play restarted clips from 0:00.
- Multi-track renders no longer bury quiet tracks: the ffmpeg `amix` mux now
  passes `normalize=0`, so declared per-segment gains are the only scaling
  (amix's default divides every input by the track count).

## [0.3.1] - 2026-07-22

### Changed
- Relaxed the HAML dependency from `~> 6.3` to `>= 6.3` so hosts on HAML 7 are
  not forced to downgrade.

## [0.3.0] - 2026-07-22

### Fixed
- Studio playback started from a scrubbed position could seek the audio before
  its metadata had loaded; the seek silently failed and the clip played from
  0:00 instead of the playhead offset. The seek is now deferred until
  `loadedmetadata`.
- Studio playback now stops on Turbo navigation (`turbo:before-visit`,
  `turbo:before-cache`) and `pagehide` — Turbo swaps the body without unloading
  the window, so a detached, still-playing audio element kept sounding under
  the next page.

## [0.2.0] - 2026-07-09

### Added
- Scene sidecar templates can now be authored in ERB (`canvas.html.erb`) as well
  as HAML — Rails resolves whichever exists, so HAML and ERB scenes can be mixed
  in one app.
- Test matrix across Rails 7.2 and 8.1 on Ruby 3.3 and 3.4, via Appraisal.

### Changed
- Lowered the minimum supported versions to Rails >= 7.2 and Ruby >= 3.3
  (previously Rails >= 8.1.3, Ruby >= 3.4).
- HAML is now a runtime dependency, so the Studio UI and HAML scenes render on
  any host without the host having to add HAML itself (fixes an ERB-only host
  crashing when mounting the Studio).

## [0.1.0] - 2026-07-08

### Added
- Initial extraction of AnimateIt into a standalone gem.
- Declarative composition DSL: `size`, `fps`, `duration`, `beat`, `audio`,
  `audio_loop`, `outputs`, `scene`, `series`.
- `Scene` render context with animation helpers (`at_global`, `at_act`,
  `beat_frame`, `beat_range`), `fixtures`, and `expose`.
- Studio UI mounted at `/animate_it` for previewing and rendering compositions.
- `VideoRenderer`: single-browser Playwright frame capture piped through FFmpeg
  to MP4/WebM/MOV/GIF, with audio mux (`adelay` + `volume` + `amix`).
- `render_animate_it_video` executable and `animate_it:render` rake task.
- `animate_it:install` generator.

[Unreleased]: https://github.com/joinbuildit/animate_it/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/joinbuildit/animate_it/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/joinbuildit/animate_it/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/joinbuildit/animate_it/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/growth-constant/animate_it/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/growth-constant/animate_it/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/growth-constant/animate_it/releases/tag/v0.1.0
