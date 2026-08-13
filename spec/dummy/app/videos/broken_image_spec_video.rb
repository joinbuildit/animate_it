class BrokenImageSpecVideo < AnimateIt::Composition
  id "broken-image-spec"
  public_player! autoplay: true
  fps 10
  size 240, 120
  duration 10.frames
  beat :broken, at: 0, length: 10.frames
  chapter :broken, beat: :broken, label: "Broken"

  class Scene < AnimateIt::Scene
    def body
      tag.img src: "/missing-visible-frame.webp", alt: "Missing frame fixture", style: "width:100%;height:100%"
    end
  end

  scene Scene
end
