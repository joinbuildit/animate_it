# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/growth-constant/animate_it/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/growth-constant/animate_it/releases/tag/v0.1.0
