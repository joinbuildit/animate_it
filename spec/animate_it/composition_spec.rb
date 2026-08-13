require "rails_helper"

RSpec.describe AnimateIt::Composition do
  before do
    AnimateIt.reset!

    scene_class = Class.new(AnimateIt::Scene) do
      def render(_view_context)
        %(<div data-local-frame="#{local_frame}">#{props[:title]}</div>)
      end
    end
    stub_const("TestMotionScene", scene_class)

    composition_class = Class.new(described_class) do
      id "test-motion"
      fps 30
      size 100, 200
      duration 2.seconds

      props do
        string :title, default: "Hello"
      end

      scene TestMotionScene, from: 1.second, duration: 1.second
    end
    stub_const("TestMotionComposition", composition_class)
  end

  after do
    AnimateIt.reset!
  end

  it "registers compositions by id" do
    expect(AnimateIt.registry.fetch("test-motion")).to eq(TestMotionComposition)
  end

  it "tracks video metadata" do
    expect(TestMotionComposition.fps).to eq(30)
    expect(TestMotionComposition.width).to eq(100)
    expect(TestMotionComposition.height).to eq(200)
    expect(TestMotionComposition.duration_in_frames).to eq(60)
  end

  it "requires an explicit public-player opt in and records playback options" do
    public_composition = Class.new(described_class) do
      id "public-motion"
      public_player! autoplay: true, loop: false
    end

    expect(TestMotionComposition).not_to be_public_player
    expect(public_composition).to be_public_player
    expect(public_composition).to be_client_driven
    expect(public_composition.public_player_options).to eq(autoplay: true, loop: false)
  end

  it "requires client-driven rendering before opting into Servo" do
    composition = Class.new(described_class)

    expect { composition.servo_compatible! }
      .to raise_error(ArgumentError, /requires client_driven/)

    composition.client_driven!
    composition.servo_compatible!

    expect(composition).to be_servo_compatible
  end

  it "builds local frame context for active timeline segments" do
    segment = TestMotionComposition.timeline.active_segments(35).first
    context = TestMotionComposition.frame_context(frame: 35, props: {}, segment:)

    expect(context.frame).to eq(35)
    expect(context.local_frame).to eq(5)
    expect(context.props).to eq(title: "Hello")
  end

  it "stores sequence presentation metadata" do
    scene_class = Class.new(AnimateIt::Scene)
    composition_class = Class.new(described_class) do
      id "metadata-motion"
      sequence from: 0, duration: 10.frames, scene: scene_class, layout: :absolute_fill, name: "Intro"
    end

    segment = composition_class.timeline.segments.first
    expect(segment.name).to eq("Intro")
    expect(segment.layout).to eq(:absolute_fill)
    expect(segment.show_in_timeline).to be(true)
  end

  it "tracks transition series metadata without rendering transition-only segments" do
    scene_class = Class.new(AnimateIt::Scene)
    composition_class = Class.new(described_class) do
      id "transition-motion"
      transition_series do
        scene scene_class, duration: 30.frames
        transition :fade, duration: 10.frames
        scene scene_class, duration: 30.frames
      end
    end

    transition = composition_class.timeline.segments.find { |segment| segment.kind == :transition }
    expect(transition.transition).to eq(:fade)
    expect(transition.duration_frames).to eq(10)
  end

  it "derives sidecar template roots from the composition class name" do
    scene = Class.new(AnimateIt::Scene) do
      def template_root
        send(:sidecar_template_root)
      end
    end

    composition_class = Class.new(described_class) do
      id "sidecar-motion"
      scene scene, duration: 10.frames
    end
    stub_const("SidecarMotionVideo", composition_class)

    context = composition_class.frame_context(frame: 0, props: {})
    instance = scene.new(context:, props: {})

    expect(instance.template_root).to eq("sidecar_motion_video")
  end
end
