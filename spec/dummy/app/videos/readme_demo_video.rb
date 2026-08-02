# Self-contained composition used for the animated README preview.
class ReadmeDemoVideo < AnimateIt::Composition
  id "readme-demo"
  client_driven!
  fps 15
  size 640, 360
  duration 5.seconds

  outputs do
    gif to: "../../assets/animate-it-demo.gif"
  end

  class Scene < AnimateIt::Scene
    word_reveal :tagline, "Rails views. In motion.", start: 23, stagger: 3, dur: 10, rise: 14

    track_vars(:demo) do
      progress = at_global([38, 62], [0, 100])

      {
        scene_opacity: at_global([0, 8, 66, 74], [0, 1, 1, 0]),
        logo_scale: at_global([4, 18, 23], [0.92, 1.04, 1]),
        chevron_one_x: "#{at_global([3, 18], [-150, 0])}px",
        chevron_two_x: "#{at_global([6, 20], [-105, 0])}px",
        chevron_three_x: "#{at_global([9, 22], [-60, 0])}px",
        wordmark_opacity: at_global([14, 27], [0, 1]),
        wordmark_y: "#{at_global([14, 27], [14, 0])}px",
        playback_opacity: at_global([32, 43], [0, 1]),
        playback_y: "#{at_global([32, 43], [10, 0])}px",
        progress_width: "#{progress}%",
        chip_one_opacity: at_global([46, 55], [0, 1]),
        chip_two_opacity: at_global([50, 59], [0, 1]),
        chip_three_opacity: at_global([54, 63], [0, 1]),
        chips_y: "#{at_global([46, 60], [9, 0])}px"
      }
    end

    text_track(:progress) do
      "#{at_global([38, 62], [0, 100]).round}%"
    end

    def body
      expose(
        tagline: reveal_words(:tagline),
        progress_label: evaluate_text_track(:progress)
      )

      tag.div(
        data: { animate_vars: "demo" },
        style: animation_vars(:demo)
      ) { render_scene_template("canvas") }
    end
  end

  scene Scene
end
