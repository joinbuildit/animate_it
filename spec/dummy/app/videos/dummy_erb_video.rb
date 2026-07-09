# ERB twin of DummyMotionVideo. Identical scene logic, but its sidecar canvas
# is authored in ERB (canvas.html.erb) instead of HAML — proving the engine
# renders scene templates in either templating language, on every Rails version
# in the test matrix.
class DummyErbVideo < AnimateIt::Composition
  id "dummy-erb"
  fps 30
  size 200, 200
  duration 15.frames

  assets_dir "tmp/animate_it"
  output_basename "dummy-erb"

  outputs do
    mp4
    png frame: 7
  end

  beat :move, at: 0, length: 15

  class Scene < AnimateIt::Scene
    def body
      expose(vars: stage_vars)
      tag.div(class: "hero-render-canvas", style: canvas_style) do
        render_scene_template("canvas")
      end
    end

    def stage_vars
      s, e = beat_range(:move)
      animation_vars(
        box_x: "#{at_global([s, e], [0, 140])}px",
        box_opacity: at_global([s, s + 5, e], [0, 1, 1])
      )
    end

    def canvas_style
      style(
        "position: relative",
        "width: 200px",
        "height: 200px",
        "background: #1a1d29",
        "overflow: hidden"
      )
    end
  end

  scene Scene
end
