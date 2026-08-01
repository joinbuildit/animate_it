require "rails_helper"

RSpec.describe AnimateIt::Tracks do
  def decode_rle(track)
    track.fetch("r").flat_map { |value, run| [value] * run }
  end

  def scoped_scene(label, multiplier)
    Class.new(AnimateIt::Scene) do
      track_vars(:root) { { op: local_frame * multiplier } }
      text_track(:counter) { "#{label}-#{local_frame}" }
    end
  end

  before do
    AnimateIt.reset!

    scene_class = Class.new(AnimateIt::Scene) do
      track_vars :root do
        {
          box_op: at_global([0, 10], [0, 1]),
          box_x: "#{at_global([0, 10], [0, 40])}px"
        }
      end
      text_track(:counter) { (local_frame / 10) * 10 }
    end
    stub_const("TrackedScene", scene_class)

    composition_class = Class.new(AnimateIt::Composition) do
      id "tracked-motion"
      fps 30
      size 100, 100
      duration 30.frames
      scene TrackedScene
    end
    stub_const("TrackedComposition", composition_class)
  end

  after { AnimateIt.reset! }

  describe "recorded samples" do
    let(:document) { TrackedComposition.track_document.as_json }

    it "samples variables and text at every frame" do
      opacity = decode_rle(document.dig("groups", "s0:root", "--box-op"))
      text = decode_rle(document.dig("texts", "s0:counter"))

      expect(opacity.length).to eq(30)
      expect(opacity.values_at(0, 5, 10, 29)).to eq(%w[0.0 0.75 1.0 1])
      expect(text.values_at(0, 10, 25)).to eq(%w[0 10 20])
    end

    it "keeps unit-suffixed strings and run-length encodes clamped regions" do
      x = decode_rle(document.dig("groups", "s0:root", "--box-x"))
      runs = document.dig("groups", "s0:root", "--box-op", "r")

      expect(x.values_at(0, 10, 29)).to eq(["0.0px", "40.0px", "40px"])
      expect(runs.last).to eq(["1", 19])
    end
  end

  describe "unset values" do
    it "leaves sampled variables unset outside the segment window" do
      stub_const("LateScene", Class.new(AnimateIt::Scene) do
        track_vars(:late) { { op: at_global([0, 5], [0, 1]) } }
      end)
      stub_const("LateComposition", Class.new(AnimateIt::Composition) do
        id "late-motion"
        duration 20.frames
        scene LateScene, from: 10, duration: 10.frames
      end)

      track = decode_rle(LateComposition.track_document.as_json.dig("groups", "s0:late", "--op"))

      expect(track.first(10)).to all(be_nil)
      expect(track.values_at(15, 19)).to eq(["1.0", "1"])
    end

    it "preserves nil and omitted variables as explicit unsets" do
      stub_const("OptionalVarScene", Class.new(AnimateIt::Scene) do
        track_vars :root do
          case local_frame
          when 0, 4 then { optional: nil }
          when 2 then { optional: "visible" }
          else {}
          end
        end
      end)
      stub_const("OptionalVarComposition", Class.new(AnimateIt::Composition) do
        id "optional-var-motion"
        duration 5.frames
        scene OptionalVarScene
      end)

      track = decode_rle(OptionalVarComposition.track_document.as_json.dig("groups", "s0:root", "--optional"))

      expect(track).to eq([nil, nil, "visible", nil, nil])
    end
  end

  describe "declarative tracks" do
    it "serializes animate keyframes in composition-global time" do
      stub_const("DelayedKfScene", Class.new(AnimateIt::Scene) do
        animate(:badge) do
          fade during: 4..12
          slide during: 4..12, from: 16
        end
      end)
      stub_const("DelayedKfComposition", Class.new(AnimateIt::Composition) do
        id "delayed-kf-motion"
        duration 40.frames
        scene DelayedKfScene, from: 20, duration: 20.frames
      end)

      animate = DelayedKfComposition.track_document.as_json.dig("groups", "s0:animate")
      expect(animate.fetch("--badge-opacity")).to eq(
        "t" => "kf", "k" => [[24, 0], [32, 1]], "e" => "ease_out", "u" => ""
      )
      expect(animate.fetch("--badge-translate-y")).to eq(
        "t" => "kf", "k" => [[24, 16], [32, 0]], "e" => "ease_out", "u" => "px"
      )
    end

    it "offsets delayed word reveals into composition-global time" do
      stub_const("DelayedRevealScene", Class.new(AnimateIt::Scene) do
        word_reveal :headline, "Two words", start: 2, stagger: 1, dur: 4
      end)
      stub_const("DelayedRevealComposition", Class.new(AnimateIt::Composition) do
        id "delayed-reveal-motion"
        duration 30.frames
        scene DelayedRevealScene, from: 10, duration: 20.frames
      end)

      opacity = DelayedRevealComposition.track_document.as_json.dig(
        "groups", "s0:textfx-headline", "--headline-w0-op"
      )
      expect(opacity.fetch("k")).to eq([[12, 0], [16, 1]])
    end
  end

  describe "segment scoping" do
    it "isolates reused variable and text names by segment" do
      stub_const("FirstScopedScene", scoped_scene("first", 1))
      stub_const("SecondScopedScene", scoped_scene("second", 2))
      stub_const("ScopedComposition", Class.new(AnimateIt::Composition) do
        id "scoped-motion"
        duration 20.frames
        scene FirstScopedScene, duration: 10.frames
        scene SecondScopedScene, from: 10, duration: 10.frames
      end)

      document = ScopedComposition.track_document.as_json

      expect(document.fetch("groups").keys).to contain_exactly("s0:root", "s1:root")
      expect(document.fetch("texts").keys).to contain_exactly("s0:counter", "s1:counter")
      expect(document.dig("groupSelectors", "s0:root")).to include('[data-animate-layer="s0/e0"]')
      expect(document.dig("groupSelectors", "s1:root")).to include('[data-animate-layer="s1/e10"]')
    end
  end

  describe "structure layers" do
    it "splits at epochs while keeping scene-local animation origins" do
      stub_const("EpochScene", Class.new(AnimateIt::Scene))
      stub_const("EpochComposition", Class.new(AnimateIt::Composition) do
        id "epoch-motion"
        duration 40.frames
        structure_epochs 30
        scene EpochScene, from: 20, duration: 20.frames
      end)

      layers = EpochComposition.track_document.as_json.fetch("layers")

      expect(layers).to match(
        [
          hash_including("sel" => '[data-animate-layer="s0/e20"]', "from" => 20, "to" => 30, "origin" => 20),
          hash_including("sel" => '[data-animate-layer="s0/e30"]', "from" => 30, "to" => 40, "origin" => 20)
        ]
      )
    end

    it "uses unique layer keys when the same scene is mounted twice" do
      stub_const("RepeatedScene", Class.new(AnimateIt::Scene))
      stub_const("RepeatedComposition", Class.new(AnimateIt::Composition) do
        id "repeated-motion"
        duration 20.frames
        scene RepeatedScene, duration: 10.frames
        scene RepeatedScene, from: 10, duration: 10.frames
      end)

      expect(RepeatedComposition.structure_layers.map(&:key)).to eq(%w[s0/e0 s1/e10])
    end
  end

  it "supports the client-driven flag and verification props matrix" do
    expect(TrackedComposition.client_driven?).to be(false)
    expect(TrackedComposition.verification_props).to eq([{}])

    TrackedComposition.client_driven!
    TrackedComposition.verification_props({}, { "title" => "Long title" })

    expect(TrackedComposition.client_driven?).to be(true)
    expect(TrackedComposition.verification_props).to eq([{}, { title: "Long title" }])
  end

  it "rejects track blocks that depend on a view context" do
    stub_const("BadScene", Class.new(AnimateIt::Scene) do
      track_vars(:bad) { { op: view_context.render(partial: "nope") } }
    end)
    stub_const("BadComposition", Class.new(AnimateIt::Composition) do
      id "bad-motion"
      duration 5.frames
      scene BadScene
    end)

    expect { BadComposition.track_document }
      .to raise_error(AnimateIt::Error, /track_vars :bad on BadScene.*without a view context/m)
  end
end
