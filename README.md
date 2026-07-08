<p align="center">
  <img src="assets/logo.svg" alt="AnimateIt" width="360">
</p>

<p align="center">
  <strong>Videos as code.</strong> Declarative, frame-driven video compositions for Rails,
  rendered with headless Chromium (Playwright) + FFmpeg.
</p>

<p align="center">
  <a href="https://github.com/growth-constant/animate_it/actions/workflows/ci.yml"><img src="https://github.com/growth-constant/animate_it/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://rubygems.org/gems/animate_it"><img src="https://img.shields.io/gem/v/animate_it.svg" alt="Gem Version"></a>
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.4-CC342D.svg" alt="Ruby >= 3.4">
</p>

---

AnimateIt lets you describe a video as a Ruby class and a HAML template, preview it
frame-by-frame in a bundled **Studio** UI, and render it to MP4/WebM/MOV/GIF. Each
frame is a real web page — so you get the full power of CSS, your app's own
components, and real data — captured by a headless browser and stitched with FFmpeg.

## Requirements

- Ruby >= 3.4, Rails >= 8.1.3
- **FFmpeg** on the PATH (rendering)
- **Node + Playwright** with a Chromium build (rendering): `npx playwright install chromium`
- **HAML** (composition sidecar templates + Studio views)

Playwright and FFmpeg are only needed when you actually render; the gem loads
Playwright lazily so production boot / asset precompile never touch it.

## Installation

```ruby
# Gemfile
gem "animate_it"
```

```bash
bundle install
bin/rails generate animate_it:install
```

The generator adds `config/initializers/animate_it.rb` and mounts the Studio in
`config/routes.rb` (development/test only):

```ruby
mount AnimateIt::Engine, at: AnimateIt.config.mount_path if Rails.env.local?
```

Visit **http://localhost:3000/animate_it** to open the Studio.

## Writing a composition

Compositions live in `app/videos/`. They auto-register (via the `id "..."` DSL)
and reload in development.

```ruby
# app/videos/hello_video.rb
class HelloVideo < AnimateIt::Composition
  id "hello"
  fps 30
  size 1080, 1080
  duration 3.seconds

  assets_dir "app/assets/images/videos"
  output_basename "hello"

  outputs do
    mp4
    gif
    png frame: 45
  end

  beat :intro, at: 0, length: 45

  class Scene < AnimateIt::Scene
    def body
      expose(vars: animation_vars(title_opacity: at_act(:intro, [0, 30], [0, 1])))
      tag.div(class: "hero-render-canvas") { render_scene_template("canvas") }
    end
  end

  scene Scene
end
```

```haml
-# app/videos/hello_video/canvas.html.haml
:css
  .title { opacity: var(--title-opacity, 1); font-size: 6rem; font-weight: 800; }
.stage{style: @vars}
  .title Hello 👋
```

Animation helpers (`at_global`, `at_act`, `beat_frame`, `beat_range`), a per-frame
CSS-variable bag (`animation_vars`), named `beat`s, and `audio` / `audio_loop`
tracks are all available. Compositions can render your app's real partials and
ViewComponents — see `AnimateIt.config.render_stylesheets` below.

## Rendering

The renderer needs your Rails **server running** (it drives a real browser against
the Studio's filmstrip endpoint).

```bash
# start the app
bin/rails server

# in another shell — render a composition's declared outputs
bin/rails 'animate_it:render[hello]'
bin/rails 'animate_it:render[hello,0..45]'   # just a frame range

# or the packaged CLI (writes to tmp/animate_it/ by default)
bundle exec render_animate_it_video hello
bundle exec render_animate_it_video hello tmp/hello.mp4
```

You can also render from the **Studio** UI: open a composition, scrub the timeline,
and click **Render Video** to watch progress live.

### Host resolution

The renderer points the browser at `ANIMATE_IT_HOST` (falling back to the legacy
`RAILS_MOTION_HOST`, then `RAILS_HOST`, then `http://127.0.0.1:3000`):

```bash
ANIMATE_IT_HOST=http://127.0.0.1:3001 bundle exec render_animate_it_video hello
```

## Configuration

```ruby
# config/initializers/animate_it.rb
AnimateIt.configure do |config|
  # Where the Studio mounts (development/test only). Default "/animate_it".
  config.mount_path = "/animate_it"

  # Host stylesheets to inject into every rendered frame. Only needed when your
  # compositions re-use host partials/components that expect their CSS. Names
  # are passed to `stylesheet_link_tag`. Default [].
  config.render_stylesheets = %w[application components/star-ratings]
end
```

Render concurrency for the Studio's background renderer is tunable via
`ANIMATE_IT_RENDER_CONCURRENCY` and `ANIMATE_IT_RENDER_STARTS_PER_SECOND`.

## Development

```bash
bin/setup                # bundle install
bundle exec rspec        # unit + request specs (uses spec/dummy)
bundle exec rubocop

# full render smoke test (needs ffmpeg + Playwright chromium)
RUN_RENDER_SMOKE=1 bundle exec rspec spec/rendering_spec.rb
```

Specs run against a minimal host app in `spec/dummy` — no external services, no
database.

## License

[MIT](MIT-LICENSE).
