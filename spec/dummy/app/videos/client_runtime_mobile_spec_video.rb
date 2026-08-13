class ClientRuntimeMobileSpecVideo < AnimateIt::Composition
  id "client-runtime-mobile-spec"
  public_player!
  fps 10
  size 120, 240
  duration 24.frames
  beat :intro, at: 0, length: 8.frames
  beat :details, at: 8.frames, length: 8.frames
  beat :finish, at: 16.frames, length: 8.frames
  chapter :intro, beat: :intro, label: "Intro"
  chapter :details, beat: :details, label: "Details"
  chapter :finish, beat: :finish, label: "Finish"

  class Scene < AnimateIt::Scene
    track_vars(:root) { { hue: local_frame * 4 } }
    text_track(:frame) { local_frame.to_s }

    def body
      tag.div(
        style: "width:120px;height:240px;background:#172b35;color:white;display:grid;place-items:center",
        data: { animate_vars: "root" }
      ) do
        safe_join([
          tag.strong("Mobile"),
          animate_text(:frame),
          view_context.animate_it_chapter_navigation(
            composition: self.class.composition_class,
            preset: :pills,
            hide_when_embedded: true,
            frame:
          )
        ])
      end
    end
  end

  scene Scene
end
