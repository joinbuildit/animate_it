# Browser integration fixture for the seekable client runtime.
class ClientRuntimeSpecVideo < AnimateIt::Composition
  id "client-runtime-spec"
  client_driven!
  public_player!
  fps 10
  size 240, 120
  duration 18.frames
  structure_epochs 5, 11

  class Scene < AnimateIt::Scene
    class << self
      attr_accessor :render_count

      def record_render!
        @render_count = render_count.to_i + 1
      end

      def reset_render_count!
        @render_count = 0
      end
    end

    track_vars(:root) do
      {
        local_x: "#{local_frame * 2}px",
        local_opacity: local_frame.fdiv(10).round(2)
      }
    end
    text_track(:counter) { "#{context.segment.name}:#{local_frame}" }
    word_reveal :headline, "Tracked words", start: 1, stagger: 1, dur: 3
    animate(:badge) do
      fade during: 0..4
      slide during: 0..4, from: 8
    end

    def body
      self.class.record_render!
      root_style = AnimateIt::Style.build(
        "position:absolute", "inset:0", "background:rgba(24,32,64,0.88)",
        "color:white", "font-family:Arial,sans-serif", "padding:8px", "box-sizing:border-box"
      )

      tag.div(
        class: "runtime-spec-scene",
        data: { scene_name: context.segment.name },
        style: root_style
      ) do
        safe_join(
          [
            generated_animation_styles,
            tag.style(<<~CSS.html_safe),
              @keyframes runtime-spec-pulse {
                from { opacity: 0.2; }
                to { opacity: 1; }
              }
            CSS
            tag.div(data: { animate_vars: "root" }, style: animation_vars(:root)) do
              safe_join(
                [
                  tag.span(evaluate_text_track(:counter), data: { animate_text: "counter" }),
                  tag.span("badge", data: { anim: "badge" }),
                  tag.span(
                    "pulse", data: { css_animation_probe: true },
                    style: "animation:runtime-spec-pulse 1s linear infinite alternate"
                  ),
                  reveal_words(:headline)
                ],
                " "
              )
            end
          ]
        )
      end
    end
  end

  scene Scene, from: 2.frames, duration: 8.frames, name: "first"
  scene Scene, from: 6.frames, duration: 8.frames, name: "second"
  scene Scene, from: 10.frames, duration: 6.frames, name: "third"
  audio_loop "spec/client-runtime.wav", duration: 18.frames, gain: 0.2
  audio "spec/client-runtime.wav", from: 6.frames, duration: 6.frames, name: "voice", gain: 0.8
end
