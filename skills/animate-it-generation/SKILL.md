---
name: animate-it-generation
description: Author animated videos, GIFs, and still images with the AnimateIt Rails gem — compositions written as a Ruby class + a HAML or ERB canvas, rendered to MP4/WebM/GIF/PNG via Playwright + FFmpeg. Use when a Rails app needs an animated hero, a product demo, a launch clip, a social ad, or a still hero rendered from the app's own components and data. Covers the composition DSL (`beat`, `animate`, `outputs`, `assets_dir`), the Studio + render pipeline, embedding on a page, rendering real app partials, motion craft, and the common gotchas.
---

# AnimateIt — animation, video, GIF, and still generation

[AnimateIt](https://rubygems.org/gems/animate_it) is a Rails engine that defines frame-driven video compositions in pure Ruby + a HAML **or** ERB canvas and renders them via Playwright (headless Chromium) + FFmpeg. One composition produces multiple output formats from the same source (transparent WebM, opaque MP4, transparent GIF, single-frame PNG). Every frame is a real web page, so anything you can render in your app — components, styles, fonts, real data — you can put in a video.

Use this skill whenever you need an animated hero, a still hero, a marketing GIF, an animated transparent WebM, a product demo, or a social ad, generated from your own Rails app.

## Install (once per app)

```ruby
# Gemfile
gem "animate_it"
```

```bash
bundle install
bin/rails generate animate_it:install   # adds config/initializers/animate_it.rb + mounts the Studio
```

The generator mounts the Studio (development/test only) at `AnimateIt.config.mount_path` (default `/animate_it`). Rendering also needs **FFmpeg** on PATH and **Playwright** with a Chromium build (`npx playwright install chromium`) — only when you actually render, not to boot the app.

## Mental model

```
app/videos/<name>_video.rb              ← Composition (timeline + outputs + scene)
app/videos/<name>_video/canvas.html.haml   (or canvas.html.erb)  ← Sidecar template
                       │
                       ▼
   AnimateIt::Composition + AnimateIt::Scene  ← timeline computes per-frame CSS variables
                       │
                       ▼
   /animate_it/compositions/<id>/filmstrip  ← Playwright loads this, screenshots each frame
                       │
                       ▼
   tmp/animate_it/<id>/frame-NNNNN.png      ← intermediate frames
                       │
                       ▼
   FFmpeg encode (one pass per declared output format)
                       │
                       ▼
   <assets_dir>/<output_basename>.{mp4,webm,gif,png}
                       │
                       ▼
   <video> tag in your app's view
```

## Quick start — minimum composition

```ruby
# app/videos/feature_hero_video.rb
class FeatureHeroVideo < AnimateIt::Composition
  id "feature-hero"          # registry key — used in URLs + the render task
  fps 30
  size 1200, 1300            # width × height in CSS px
  duration 10.seconds

  assets_dir "app/assets/images/videos"   # where declared outputs are written
  output_basename "feature-hero"          # filename stem (defaults to id)

  outputs do
    mp4
    webm
    gif
    png frame: 0             # first-frame poster
  end

  # Named time markers — referenced as symbols in `animate` (`during: :intro`).
  beat :intro, at: 0,    length: "1s"
  beat :main,  at: "1s", length: "6s"
  beat :outro, at: "7s", length: "3s"

  class HeroScene < AnimateIt::Scene
    template :canvas          # → app/videos/feature_hero_video/canvas.html.{haml,erb}

    animate :title do
      fade  during: :intro
      slide during: :intro, from: 16       # translateY 16px → 0
    end

    animate :widget do
      fade  keyframes: { 60 => 0, 90 => 1, 270 => 1, 290 => 0 }
      slide during: 60..90, from: 16
    end
  end
end
```

The canvas only needs the `data-anim` hooks — the framework injects the
`[data-anim="title"] { opacity: var(--title-opacity, 0); transform: … }` CSS for
every `animate :name`. Write it in **HAML**:

```haml
-# app/videos/feature_hero_video/canvas.html.haml
:css
  .feature-hero-card { width: 1100px; }
.feature-hero-card{data: { anim: 'title' }}
  %h1 Feature title
.feature-hero-widget{data: { anim: 'widget' }}
```

…or **ERB** — pick whichever your app uses (you can mix engines across scenes):

```erb
<%# app/videos/feature_hero_video/canvas.html.erb %>
<style>.feature-hero-card { width: 1100px; }</style>
<div class="feature-hero-card" data-anim="title"><h1>Feature title</h1></div>
<div class="feature-hero-widget" data-anim="widget"></div>
```

Auto-mount picks up the single nested `Scene` subclass — no explicit `scene HeroScene` line needed (unless you declare audio; see below).

## Composition DSL

Class-level on `AnimateIt::Composition`:

| Method | Purpose |
|---|---|
| `id "feature-hero"` | Registry key. Required. Used in URLs + the render task. |
| `fps 30` | Frame rate. |
| `size 1200, 1300` | Width × height in CSS px. |
| `zoom 1.1` | CSS `zoom` on `<body>` in the frame layout. Magnifies **layout too** — inner content must fit `(viewport_width − 2×padding) / zoom` or it clips on the right. |
| `duration 10.seconds` | Total length. Accepts `30.frames`, `Integer`, `ActiveSupport::Duration`, or time strings (`"1.5s"`, `"300ms"`, `"1m30s"`). |
| `assets_dir "..."` | Repo-relative output directory. |
| `output_basename "..."` | Filename stem; defaults to `id`. |
| `outputs do … end` | Per-format destinations — `mp4`, `webm`, `gif`, `mov`, `png_sequence`, `png frame: N`. Pass `to: "..."` to override a path. |
| `beat :name, at:, length:` | Named time marker. Accepts frames, durations, or time strings. |
| `props do … end` | Prop schema for parameterized renders (Studio prop editor). |
| `audio "clip.mp3", from:, duration:` | Place an audio clip (see Audio, below). |
| `audio_loop "bg.mp3", duration:, gain:` | Loop background music. |
| `voice_over "vo.mp3", at: :intro, gain:` | Voice-over aligned to a beat. |

## Scene DSL — `animate :name { … }`

Class-level on `AnimateIt::Scene`:

| Method | Purpose |
|---|---|
| `template :canvas` | Sidecar name (default `:canvas`). Resolves to `app/videos/<comp>/<name>.html.{haml,erb}`. |
| `canvas_class "hero-render-canvas"` | Outer wrapper class on the auto-generated `<div>`. |
| `animate :name do … end` | Declare an animatable `[data-anim="name"]` element. |

Inside `animate :name do … end`:

```ruby
fade  during: 10..30                                    # opacity 0→1 over a frame range
fade  during: :intro                                    # …from a named beat
fade  keyframes: { 60 => 0, 90 => 1, 150 => 1, 170 => 0 }
fade  in: 10..30, out: 280..300                         # in then out
slide during: :intro, from: 16, to: 0                   # translateY (axis: :x for horizontal)
scale during: 60..90, from: 1.0, to: 1.05
css   :max_height, during: 60..90, from: 0, to: 300, unit: "px"   # anything else
css   :background, keyframes: { 60 => "white", 90 => "#f3fbfa" }
```

## Rendering

**Prerequisite:** the Rails server must be running so Playwright can load the filmstrip.

```bash
bin/rails server                          # in one shell

bin/rails 'animate_it:render[feature-hero]'        # all declared outputs (quote brackets in zsh)
bin/rails 'animate_it:render[feature-hero,30..120]'  # just a frame range (fast iteration)
bin/rails 'animate_it:render[feature-hero,80]'       # a single frame
bin/rails animate_it:render_all                     # every registered composition

# or the packaged CLI (writes to tmp/animate_it/ by default):
bundle exec render_animate_it_video feature-hero
bundle exec render_animate_it_video feature-hero tmp/out.mp4
```

You can also render from the **Studio** UI (`/animate_it`): open a composition, scrub the timeline, click **Render Video** to watch progress live. A 15s × 30fps composition takes ~3–4 min (450 frames + encodes); the frame-range arg pays for itself when iterating on one moment.

In development, edits to `app/videos/**/*.rb` reload automatically.

## Output palette — pick by browser support + transparency need

| Format | Transparent | Use for |
|---|---|---|
| `webm` | ✅ (vp9/yuva420p) | **Default for a transparent hero** (Chrome/Firefox/Edge). |
| `mp4` | ❌ (h.264/yuv420p) | Universal video; **flattens onto black** if the canvas was transparent. |
| `gif` | ✅ | Fallback where WebM-alpha is unsupported (older Safari). |
| `mov` | ✅ (prores 4444) | Editor hand-off — too big for the web. |
| `png_sequence` | ✅ | Hand-off to a video editor. |
| `png frame: N` | ✅ | Poster for the `<video>` tag, or a fully-still hero. |

For a typical page hero, declare `mp4 / webm / gif / png frame: 0`: WebM gives transparent autoplay, MP4 covers Safari, GIF is the worst-case fallback, PNG paints instantly.

## Embedding on a page

Native `<video>` with a fallback chain and a poster:

```erb
<video autoplay loop muted playsinline preload="metadata"
       poster="<%= asset_path('videos/feature-hero.png') %>"
       style="width:100%; max-width:720px; height:auto; background:transparent;">
  <source src="<%= asset_path('videos/feature-hero.webm') %>" type="video/webm">
  <source src="<%= asset_path('videos/feature-hero.mp4') %>"  type="video/mp4">
  <%= image_tag 'videos/feature-hero.gif' %>
</video>
```

Use `preload="metadata"` (not `auto`) with a poster: the PNG becomes the LCP and paints instantly while only codec headers download up front; `auto` starts the full WebM download and tanks LCP.

## Rendering your app's real partials (visually pinned to production)

For heros that should be indistinguishable from the live product, render your **actual partials/components** with FactoryBot-built records instead of duplicating markup. The Scene exposes helpers for this (`lib/animate_it/view_helpers.rb`):

- `build_factory(name, *traits, **attrs)` / `build_stubbed(name, *traits, **attrs)` — wrap FactoryBot with a clear error if it isn't loaded.
- `stub_methods(obj, **stubs)` — define singleton-method stubs; lambda values are called lazily, non-callable values auto-wrap. Also a class method on `AnimateIt::Scene`.
- `render_partial(partial, locals:, **opts)` — render a host partial.
- `render_scene_template(name, **opts)` — render the sidecar.
- `expose(*keys, from:, **ivars)` — push ivars onto the sub-render's view context (`assigns:` doesn't propagate through template renders) so the sidecar can read `@job`, `@user`, etc.

```ruby
class HeroScene < AnimateIt::Scene
  disable_fragment_caching!                # see determinism pin #3

  fixtures(seed: 20_251_114) do            # lazy, memoized once per process, Faker seeded
    company = build_stubbed(:company, id: 1, created_at: Time.utc(2025, 1, 1))
    job     = build_stubbed(:job, id: 1, company:, created_at: Time.utc(2025, 1, 1))
    { company:, job: }
  end

  def body
    expose(:job, from: fixtures)
    tag.div(class: canvas_class) { render_partial("jobs/card", locals: { job: @job }) }
  end
end
```

**Determinism is three pins** (the renderer treats every frame as an independent request):
1. `seed:` on `fixtures` — pins `Faker::Config.random` before the block runs.
2. Explicit `id:` / `created_at:` / `updated_at:` / `email:` on every `build_stubbed` — FactoryBot sequences and `SecureRandom` defaults aren't Faker-seeded.
3. `disable_fragment_caching!` — dev has caching on; a `cache do … end` block keyed on `updated_at` (stable across frames) would serve frame 1's HTML for every frame.

`build_stubbed` doesn't stub association queries — stub the ones the partial calls with `stub_methods(record, feedbacks: -> { Feedback.none }, some_flag?: false)`.

### CSS for host partials — `config.render_stylesheets`

A sidecar rendered via `view_context.render(template:)` runs in a **sub-renderer with its own view context**, so any on-demand stylesheet queue (`add_stylesheet`-style helpers) never reaches the engine's frame layout. Declare the host CSS bundles your partials need statically:

```ruby
# config/initializers/animate_it.rb
AnimateIt.config.render_stylesheets = %w[application components/star-ratings]
```

These are passed to `stylesheet_link_tag` in the frame layout. The Studio routes are dev-only, so loading a few extra bundles is free.

## Motion craft — what makes a hero actually land

The DSL is the easy part; a composition that renders cleanly can still be flat or off-brand. Decide the **story** before writing a `beat`.

- **Lead with one idea, hold it, then move.** A hero is a poster, not a demo — text and key visuals are poster-scale. Commit the first 2–3s to a single value prop; each later beat adds one new idea, never restates.
- **The first 2 seconds decide everything.** Plan the hook first. On silent autoplay the opening frame must communicate before motion starts — the poster PNG *is* the hook for a paused viewer.
- **Readability is a timing budget.** Every line must settle and *hold* long enough to read: a short label/number ~0.8s (~24 frames @30fps), a sentence ~0.3s per word. Always **fast-in, then hold** — never fast-in, then gone. Keep pace high through cuts, never by flashing text faster.
- **Show the real thing.** At least one beat should show actual product UI/data (render real partials) — not abstract filler.
- **Be specific.** Use your product's real feature names and claims; ban generic SaaS filler ("streamline your workflow").
- **Easing & staging** (Disney's principles, adapted): entrances `ease-out` (arrive fast, settle gently), exits `ease-in`; never linear for motion (only for progress bars); keep deformation subtle (`scale(0.95–1.05)`, never `scale(0)`); one focal point at a time; dim/quiet the background behind a focal reveal; stagger groups by ~30–80ms, never more.
- **Justified motion.** Every animation answers "why does this move?" When unsure whether motion helps, the strongest move is often to delete it.

**A starting timeline** (adapt): `Hook (2–3s) → Reveal (2–4s) → 1–3 sharp highlights (5–12s) → Payoff/logo (2–4s)`.

Match `size(...)` to the channel: landscape `1920×1080` for site/YouTube, square `1080×1080` for feed, vertical `1080×1920` for Stories/Reels. Square and vertical force bigger type and fewer words per frame — design for the smallest viewport.

## Audio (optional)

Sound is placed with `audio` / `audio_loop` / `voice_over`; AnimateIt resolves paths under `app/audio/`. Bare-integer `from:`/`duration:` mean **frames**; `Duration`/`"2s"` mean seconds. Default to one tasteful music bed + a few well-timed SFX; reach for silence only when the tone calls for it.

- **You supply the audio files.** AnimateIt does not generate audio. **Ask the user** whether they have audio assets or access to a generation tool (e.g. ElevenLabs, or a royalty-free library). If they don't, offer to ship the hero **without audio** (perfectly fine for autoplay-muted page heroes) or to drop in a bring-your-own royalty-free bed. Don't assume any AI generation account exists.
- **License caveat — flag before any public/paid placement.** Whatever bed you use, confirm its license permits the placement (ad, live landing page) before shipping. Internal previews are lower-risk; still flag it.
- **Sync accents to the beat.** Land card-slides, number ticks, and logo reveals on strong beats (`frames_per_beat = fps × 60 / bpm`). Keep music low (`gain: ~0.5`) under SFX/voice. Cues are hints — never let beat-chasing hurt readability.
- **Reactive visuals, subtly.** Modulate *existing* elements with audio energy if you like; never add waveform/equalizer graphics or strobing.

## Multi-act compositions (cross-fading sidecars)

When a composition crossfades between multiple sidecars (e.g. prompt → connect → chat), override `body` instead of the single-act `animate` DSL:

```ruby
beat :prompt,  at: 0,   length: 130
beat :connect, at: 130, length: 145

class HeroScene < AnimateIt::Scene
  def body
    tag.div(class: canvas_class, style: canvas_style) do
      safe_join([prompt_act, connect_act])
    end
  end

  def prompt_act
    absolute_fill(style: act_style(prompt_opacity, prompt_vars)) { render_scene_template("prompt") }
  end
  # Each act uses its own local frame so its keyframes start at 0; the outer
  # envelope (prompt_opacity…) uses composition local_frame for the crossfade.
end
```

Trade-off: you lose the auto-generated `[data-anim]` CSS and bind `animation_vars(...)` yourself in the sidecar.

## Common gotchas

- **MP4 is never transparent.** h.264 `yuv420p` has no alpha; a transparent canvas flattens onto black. Use WebM for transparency.
- **Stimulus / JS controllers do NOT run inside the captured frame.** Anything a controller would populate at runtime must be rendered by the sidecar directly (or an inline `<script>` that runs before capture). Set `document.documentElement.dataset.animateItReady = "1"` after your DOM mutations — the layout waits on that flag before screenshotting.
- **CSS keyframe/time-based animations don't sync with discrete frame capture.** Spinners, blinking carets, `::after { animation: … }` all capture the same state every frame. Drive them from a CSS variable you set per-frame from the Scene instead.
- **Beats live on the composition**, not the scene class — declare them at the composition level; scenes look them up by name.
- **Declaring audio suppresses single-scene auto-mount.** `audio`/`audio_loop`/`voice_over` add a timeline segment, and auto-mount bails when segments exist. Symptom: every frame renders blank. Fix: add an explicit `scene HeroScene` at the **end** of the composition class.
- **GIF can't render once audio is declared** (`format=gif doesn't support audio`). Render the MP4 first (it leaves PNGs in `tmp/animate_it/<id>/`), then build the GIF from those frames directly: `ffmpeg -framerate 30 -i frame-%05d.png -vf "fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse" -loop 0 out.gif`.
- **`background: transparent` fights app body styles.** The engine frame layout already forces `body, main, .hero-render-canvas { background-color: transparent !important }`; render inside it.
- **Playwright is a dev-only dependency.** The renderer lazy-requires it, so production boot / asset precompile never touch it.

## File references (gem source)

- Composition DSL — `lib/animate_it/composition.rb`
- Scene + animate DSL — `lib/animate_it/scene.rb`, `animation.rb`
- Beats / Outputs — `lib/animate_it/beats.rb`, `output.rb`
- View helpers (factories, expose, stub_methods) — `lib/animate_it/view_helpers.rb`
- Renderer — `lib/animate_it/video_renderer.rb`
- Config (`mount_path`, `render_stylesheets`) — `lib/animate_it/configuration.rb`
