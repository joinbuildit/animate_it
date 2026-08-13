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
  <a href="https://github.com/joinbuildit/animate_it/actions/workflows/ci.yml"><img src="https://github.com/joinbuildit/animate_it/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://rubygems.org/gems/animate_it"><img src="https://img.shields.io/gem/v/animate_it.svg" alt="Gem Version"></a>
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.3-CC342D.svg" alt="Ruby >= 3.3">
</p>

---

[Remotion](https://www.remotion.dev/) made it possible to build videos in React.
**AnimateIt brings the same idea to Ruby on Rails** — without React, a JavaScript
project, or a video editor.

You describe a video as a Ruby class and a HAML or ERB template, preview it in a
bundled **Studio** UI, and render it to MP4/WebM/MOV/GIF. The declarative runtime
renders the template once per structural layer, records compact animation tracks,
and seeks those tracks in the browser. You still get your app's own components,
styles, fonts, and real data without asking Rails to render every frame.

It's built for indie hackers and Rails developers who want to promote their projects
with polished product demos, launch clips, and social ads — reusing the UI they've
already built, staying in Ruby, and skipping the whole "learn a video editor" detour.

<p align="center">
  <img src="assets/animate-it-demo.gif" alt="AnimateIt turns a Ruby composition into smooth, seekable browser animation" width="640">
</p>

<p align="center">
  <em>A five-second Ruby composition rendered by AnimateIt's client-driven browser runtime.</em><br>
  <a href="https://github.com/joinbuildit/animate_it/blob/main/spec/dummy/app/videos/readme_demo_video.rb">View the Ruby composition</a>
  ·
  <a href="https://github.com/joinbuildit/animate_it/blob/main/spec/dummy/app/videos/readme_demo_video/canvas.html.erb">View the HTML/CSS template</a>
</p>

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

## Quick examples

These examples use one small composition so you can see the complete path from
Ruby to a production Rails page without starting from the larger reference
example below.

### Fade and move an element

Create a composition with two beats. `track_vars` calculates ordinary CSS
custom properties from the current frame, so the template stays plain HTML and
CSS.

```ruby
# app/videos/welcome_video.rb
class WelcomeVideo < AnimateIt::Composition
  id "welcome"
  client_driven!
  public_player! autoplay: false, loop: true

  fps 30
  size 1200, 630
  duration 4.seconds

  beat :intro, at: 0, length: 60
  beat :details, at: 60, length: 60

  chapter :intro, beat: :intro, label: "Welcome"
  chapter :details, beat: :details, label: "Details"

  class Scene < AnimateIt::Scene
    track_vars :root do
      {
        title_opacity: at_global([0, 24], [0, 1]),
        title_y: "#{at_global([0, 24], [20, 0])}px"
      }
    end

    def body
      absolute_fill(vars: :root) { render_scene_template("canvas") }
    end
  end

  scene Scene
end
```

```haml
-# app/videos/welcome_video/canvas.html.haml
:css
  .welcome-title {
    opacity: var(--title-opacity);
    transform: translateY(var(--title-y));
    font: 700 72px/1.1 system-ui;
  }

.welcome-title Welcome to our product
```

Open `/animate_it/compositions/welcome` in development to scrub through the
frames. The animation is deterministic: seeking back to frame 12 always
produces the same opacity and position.

### Put it on a Rails page

Mount the engine in every environment where the allowlisted public player
should work:

```ruby
# config/routes.rb
mount AnimateIt::Engine, at: "/animate_it"
```

Then add the poster-first player to any ERB view. The built-in pill preset makes
the two chapters clickable and keeps their progress synchronized with playback.

```erb
<%= animate_it_embed(
  "welcome",
  poster: image_path("welcome-poster.webp"),
  navigation: { preset: :pills },
  play_when_visible: 2.0 / 3
) %>
```

For the smallest possible iframe without lifecycle or chapter controls, use:

```erb
<%= animate_it_player "welcome", title: "Welcome product demo" %>
```

### Use cards instead of pills

Chapter navigation is headless. The same animation state can drive cards,
tabs, thumbnails, timeline steps, or custom SVG instead of the pill preset:

```erb
<%= animate_it_embed("welcome", poster: image_path("welcome-poster.webp")) do |embed| %>
  <%= embed.chapter_navigation(class: "demo-cards") do |chapter| %>
    <%= chapter.button(class: "demo-card") do %>
      <strong><%= chapter.label %></strong>
      <span class="demo-card__progress"></span>
    <% end %>
  <% end %>
<% end %>
```

```css
.demo-card__progress {
  display: block;
  width: calc(var(--animate-it-chapter-progress) * 100%);
  height: 3px;
  margin-top: 0.5rem;
  background: #28d2bc;
}
```

Each button also receives `data-chapter-state="completed|current|upcoming"`, so
you can style every state without adding JavaScript.

## Writing a composition

Compositions live in `app/videos/`. They auto-register (via the `id "..."` DSL)
and reload in development.

```ruby
# app/videos/hello_video.rb
class HelloVideo < AnimateIt::Composition
  id "hello"
  client_driven!
  # Explicitly certify this composition before using the experimental Servo backend.
  # servo_compatible!
  fps 30
  size 1080, 1080
  duration 3.seconds

  props do
    integer :counter_start, default: 0
  end
  verification_props({}, { counter_start: 100 })

  assets_dir "app/assets/images/videos"
  output_basename "hello"

  outputs do
    mp4
    gif
    png frame: 45
  end

  beat :intro, at: 0, length: 45

  class Scene < AnimateIt::Scene
    track_vars :root do
      { title_opacity: at_act(:intro, [0, 30], [0, 1]) }
    end

    text_track(:counter) { (props[:counter_start] + local_frame).to_s }

    def body
      absolute_fill(vars: :root) do
        safe_join([render_scene_template("canvas"), animate_text(:counter)])
      end
    end
  end

  scene Scene
end
```

```haml
-# app/videos/hello_video/canvas.html.haml
:css
  .title { opacity: var(--title-opacity, 1); font-size: 6rem; font-weight: 800; }
.stage
  .title Hello 👋
```

Animation helpers (`at_global`, `at_act`, `beat_frame`, `beat_range`), sampled
CSS variables (`track_vars`), dynamic text (`text_track`), named `beat`s, and
`audio` / `audio_loop` tracks are available. Compositions can render your app's
real partials and ViewComponents — see `AnimateIt.config.render_stylesheets`
below.

### Browser playback runtime

`client_driven!` switches export and Studio playback to `/player`. Rails renders
each structural layer once and records a schema-v2 track document; then
`window.__animateIt.setFrame(frame)` updates CSS variables, text, layer
visibility, word reveals, and native CSS/Web Animations without another frame
request.

Use `structure_epochs` only when a template's DOM shape changes. Each epoch adds
one pre-rendered layer. Track schema v2 scopes bindings to their timeline segment;
the player still accepts v1 documents and rejects unknown versions.

```ruby
structure_epochs 60, 120

class Scene < AnimateIt::Scene
  track_vars(:card) { { x: "#{at_global([0, 30], [-20, 0])}px" } }
  text_track(:score) { (progress * 100).round }

  def body
    absolute_fill(vars: :card) do
      safe_join([render_scene_template("canvas"), animate_text(:score)])
    end
  end
end
```

### Production frontend playback

Public playback is opt-in per composition. `public_player!` enables the
standalone browser clock, Play/Pause control, looping, and synchronized
music/voice/SFX. It does not expose Studio, frame, filmstrip, props, or render
endpoints, and public playback always uses the composition's default props.

```ruby
class HelloVideo < AnimateIt::Composition
  id "hello"
  public_player! autoplay: false, loop: true
  beat :intro, at: 0, length: 45
  beat :details, at: 45, length: 45
  chapter :intro, beat: :intro, label: "Intro"
  chapter :details, beat: :details, label: "Details"
  # ...
end
```

Mount the engine in every environment, then embed the allowlisted composition
from a host view:

```ruby
# config/routes.rb
mount AnimateIt::Engine, at: AnimateIt.config.mount_path
```

```erb
<%= animate_it_player "hello", title: "Hello product demo" %>
```

`animate_it_player` remains the low-level responsive iframe. For a complete
production embed with accessible chapter navigation, a poster-first handoff,
visibility playback, reduced-motion behavior, and offscreen pausing, use:

```erb
<%= animate_it_embed(
  "hello",
  poster: image_path("hello.webp"),
  variants: [
    {
      media: "(max-width: 767px)",
      composition: "hello-mobile",
      poster: image_path("hello-mobile.webp")
    }
  ],
  navigation: { preset: :pills, mobile: :carousel },
  load_when_visible: 0.25,
  play_when_visible: 2.0 / 3
) %>
```

Responsive compositions may use different sizes and chapter frames, but must
declare the same ordered chapter names and labels. The embed swaps by media
query and restores the current chapter by name.

The pill rail is optional. Build cards, tabs, thumbnails, dots, or custom SVG
with the headless Rails builder:

```erb
<%= animate_it_embed("hello", poster: image_path("hello.webp")) do |embed| %>
  <%= embed.chapter_navigation(class: "product-demo-cards") do |chapter| %>
    <%= chapter.button(class: "product-demo-card") do %>
      <strong><%= chapter.label %></strong>
    <% end %>
  <% end %>
<% end %>
```

Every control receives `data-chapter-state`, `data-chapter-position`, and the
normalized CSS variables `--animate-it-chapter-progress`,
`--animate-it-chapter-active`, and `--animate-it-chapter-complete`. The player
emits `animateit:ready`, `animateit:framechange`, `animateit:chapterchange`,
`animateit:play`, `animateit:pause`, `animateit:ended`, and `animateit:error`
events. Host commands use a source-checked same-origin message
boundary instead of reaching into iframe globals.

For direct player integrations, `window.AnimateItPlayer` exposes `play`,
`pause`, `toggle`, `seek`, `seekChapter`, `playing`, and `currentFrame`.
`window.AnimateItTransport` remains an alias for compatibility with 0.4.

To include the same chapter visualization in Studio and rendered media:

```erb
<%= animate_it_chapter_navigation preset: :pills, hide_when_embedded: true %>
```

The iframe still renders each structural layer once and advances entirely in
the browser. Audio-capable players fall back to the visible Play button when
the browser blocks autoplay.

### Migrating a custom iframe controller

Replace application-owned iframe scaling, `IntersectionObserver`, poster
crossfade, breakpoint swapping, frame polling, and `contentWindow` transport
calls with `animate_it_embed`. Keep application CSS by overriding the documented
`--animate-it-*` tokens or render completely custom chapter controls through the
headless builder. Continue using `animate_it_player` when the application truly
needs to own the entire lifecycle.

### HAML or ERB

Scene sidecar templates can be authored in **HAML** (`canvas.html.haml`) or
**ERB** (`canvas.html.erb`) — Rails resolves whichever file exists, so you can
mix engines across scenes. The HAML canvas above is equivalent to:

```erb
<%# app/videos/hello_video/canvas.html.erb %>
<style>.title { opacity: var(--title-opacity, 1); font-size: 6rem; font-weight: 800; }</style>
<div class="stage">
  <div class="title">Hello 👋</div>
</div>
```

The gem bundles HAML for its own Studio UI, so you never need to add HAML to your
app to use it — ERB-only apps work out of the box.

## Rendering

The renderer needs your Rails **server running**. It drives a real browser
against `/player` for client-driven compositions and the legacy `/filmstrip`
endpoint for other compositions.

```bash
# start the app
bin/rails server

# in another shell — render a composition's declared outputs
bin/rails 'animate_it:render[hello]'
bin/rails 'animate_it:render[hello,0..45]'   # just a frame range

# compare /player with the legacy /filmstrip (step 1 checks every frame)
bin/rails 'animate_it:verify[hello,1]'
bin/rails animate_it:verify_all

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

  # Optional Servo worker. :auto uses Servo only for compositions that call
  # `servo_compatible!` and falls back to Playwright on worker failures.
  config.capture_backend = :auto
  config.servo_endpoint = "http://127.0.0.1:4178"
  config.servo_allowed_origins = ["http://127.0.0.1:3000"]
  config.servo_version = ENV.fetch("ANIMATE_IT_SERVO_VERSION", "0.4.0")

  # Opt in to short-lived private render pages and PNG controller responses.
  config.internal_rendering = Rails.env.local?
  config.render_asset_origins = ["https://cdn.example.com"]
  config.render_cache_version = ENV.fetch("ANIMATE_IT_RENDER_CACHE_VERSION", "development")
end
```

With internal rendering enabled, a controller can return a generated still:

```ruby
render animate_it: {
  composition: "hello",
  frame: 45,
  props: { counter_start: 100 },
  cache: true
}
```

The response is an inline PNG with an ETag. Props are stored in a 60-second
opaque cache ticket rather than the render URL. Unknown or incorrectly typed
props are rejected, and asset props may use only relative URLs or configured
origins. A shared, writable Rails cache is required.

For local development with AnimateIt 0.6 installed, add the two optional
processes below to the host application's `Procfile.dev`. The capture root must
contain AnimateIt's normal `tmp/animate_it` frame directories.

```procfile
servo_engine: servoshell --headless --webdriver 7000 --window-size 1200x630 about:blank
servo_worker: cargo run --manifest-path $(bundle show animate_it)/servo-renderer/Cargo.toml -- --allowed-origins http://127.0.0.1:3000 --capture-root $PWD/tmp/animate_it --webdriver-url http://127.0.0.1:7000
```

Servo is pinned to 0.4.0 for this experimental integration. The dedicated
`Servo compatibility` workflow verifies the Rust protocol and performs an
opt-in capture with the checksum-pinned official Servo binary.

When one composition declares multiple formats for the same frame range,
AnimateIt captures the ordered Chromium frames once and reuses them for each
encoder. Studio rendering intentionally keeps one sequential capture stream so
frame ordering, progress, and cancellation stay deterministic.

## Deterministic asset preflight

Host applications can record local composition inputs in
`config/animate_it_assets.yml`. `bin/rails animate_it:preflight` checks that each
file exists, matches its SHA-256 checksum, and has a provenance provider. Media
stays in the host app and is not packaged in the gem.

```yaml
version: 1
assets:
  - path: app/audio/launch/music.mp3
    kind: music
    compositions: [hello]
    sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    provenance:
      provider: elevenlabs
      generated_with_ai: true
      model_id: not-recorded
      generation_id: not-recorded
```

For parameterized compositions, declare `verification_props` or override them
at the command line:

```bash
ANIMATE_IT_PROPS_JSON='{"title":"Variant"}' bin/rails 'animate_it:verify[hello,1]'
ANIMATE_IT_PROPS_MATRIX_JSON='[{}, {"title":"Variant"}]' bin/rails animate_it:verify_all
```

Verification requires a running server and writes comparison screenshots under
`tmp/animate_it/verify`.

To compare a `servo_compatible!` player with Servo instead of comparing the
Chromium player with the legacy filmstrip, set
`ANIMATE_IT_VERIFY_BACKEND=servo`. Certification also samples chapter
boundaries and rejects compositions that depend on native CSS/Web Animations.

## Claude skill

If you use [Claude Code](https://claude.com/claude-code), this repo ships an
Agent Skill that teaches Claude how to author AnimateIt compositions — the DSL,
the render pipeline, embedding, rendering your app's real partials, motion
craft, and the gotchas. Install it into your project's `.claude/skills/`:

```bash
npx animate-it-skills          # copies the skill into ./.claude/skills
```

The skill source lives in [`skills/`](skills/).

## Development

```bash
bin/setup                # bundle install
bundle exec rspec        # unit + request specs (uses spec/dummy)
bundle exec rubocop
gem build animate_it.gemspec

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
