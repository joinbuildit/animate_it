<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo.svg" alt="AnimateIt" width="360">
  </picture>
</p>

<p align="center">
  <strong>Remotion for Rails.</strong> Make videos from your app's own components and data,
  written in Ruby — no React, no video editor, no After Effects.
</p>

<p align="center">
  <a href="https://github.com/growth-constant/animate_it/actions/workflows/ci.yml"><img src="https://github.com/growth-constant/animate_it/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://rubygems.org/gems/animate_it"><img src="https://img.shields.io/gem/v/animate_it.svg" alt="Gem Version"></a>
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.4-CC342D.svg" alt="Ruby >= 3.4">
</p>

---

[Remotion](https://www.remotion.dev/) made it possible to build videos in React.
**AnimateIt brings the same idea to Ruby on Rails** — without React, a JavaScript
project, or a video editor.

You describe a video as a Ruby class and a HAML template, preview it frame-by-frame
in a bundled **Studio** UI, and render it to MP4/WebM/MOV/GIF. Every frame is a real
web page, so you get the full power of CSS and — crucially — **your app's own
components, styles, fonts, and real data**. A headless browser captures each frame
and FFmpeg stitches them into a video.

It's built for indie hackers and Rails developers who want to promote their projects
with polished product demos, launch clips, and social ads — reusing the UI they've
already built, staying in Ruby, and skipping the whole "learn a video editor" detour.

## Requirements

- Ruby >= 3.3, Rails >= 7.2 (tested against Rails 7.2 and 8.1)
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

### HAML or ERB

Scene sidecar templates can be authored in **HAML** (`canvas.html.haml`) or
**ERB** (`canvas.html.erb`) — Rails resolves whichever file exists, so you can
mix engines across scenes. The HAML canvas above is equivalent to:

```erb
-# app/videos/hello_video/canvas.html.erb
<style>.title { opacity: var(--title-opacity, 1); font-size: 6rem; font-weight: 800; }</style>
<div class="stage" style="<%= @vars %>">
  <div class="title">Hello 👋</div>
</div>
```

The gem bundles HAML for its own Studio UI, so you never need to add HAML to your
app to use it — ERB-only apps work out of the box.

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

# run the suite against a specific Rails version (see Appraisals)
bundle exec appraisal install
bundle exec appraisal rails-7.2 rspec
bundle exec appraisal rails-8.1 rspec
```

Specs run against a minimal host app in `spec/dummy` — no external services, no
database.

## Credits

AnimateIt is inspired by [**Remotion**](https://www.remotion.dev) — the framework
that pioneered making videos programmatically in React. AnimateIt brings that
"videos as code" idea to the Ruby on Rails ecosystem, natively and without React.
Huge thanks to the Remotion team for the inspiration.

## License

AnimateIt is released under the [**MIT License**](MIT-LICENSE) — free and open source,
with **no restrictions on commercial or business use**. Individuals, startups,
agencies, and companies of any size can use it in open-source and closed-source
projects at no cost, forever. No paid tiers, no seat limits.
