require "rails_helper"

RSpec.describe AnimateIt::AnimationHelpers do
  let(:scene_class) do
    klass = Class.new(AnimateIt::Scene)
    klass.composition_class = composition_class
    klass
  end

  let(:composition_class) do
    Class.new(AnimateIt::Composition) do
      id "animation-helpers-test"
      fps 30
      size 100, 100
      duration 100.frames

      beat :intro, at: 0, length: 30
      beat :outro, at: 60, length: 20
    end
  end

  def scene_at(frame)
    context = composition_class.frame_context(frame:, props: {})
    scene_class.new(context:, props: context.props)
  end

  describe "#act_local" do
    it "returns local_frame minus the beat's start_frame" do
      expect(scene_at(70).act_local(:outro)).to eq(10)
      expect(scene_at(5).act_local(:intro)).to eq(5)
    end

    it "can return negative values for frames before the beat" do
      expect(scene_at(40).act_local(:outro)).to eq(-20)
    end
  end

  describe "#at_act" do
    it "interpolates linearly within beat-local frame space" do
      expect(scene_at(15).at_act(:intro, [0, 30], [0, 1.0], easing: :linear))
        .to be_within(0.001).of(0.5)
    end

    it "applies the default ease_out curve" do
      expect(scene_at(15).at_act(:intro, [0, 30], [0, 1.0])).to be_within(0.001).of(0.75)
    end

    it "clamps below the beat's start_frame" do
      expect(scene_at(0).at_act(:outro, [0, 20], [0, 1.0])).to eq(0)
    end

    it "clamps above the beat's end_frame" do
      expect(scene_at(99).at_act(:outro, [0, 20], [0, 1.0])).to eq(1)
    end
  end

  describe "#at_global" do
    it "interpolates linearly against composition-level local_frame" do
      expect(scene_at(50).at_global([0, 100], [0, 1.0], easing: :linear))
        .to be_within(0.001).of(0.5)
    end

    it "clamps outside the input range" do
      expect(scene_at(0).at_global([20, 80], [0, 1.0])).to eq(0)
      expect(scene_at(99).at_global([20, 80], [0, 1.0])).to eq(1)
    end
  end

  describe "#beat_frame" do
    it "returns the beat's start_frame" do
      expect(scene_at(0).beat_frame(:outro)).to eq(60)
    end

    it "raises AnimateIt::Error for an unknown beat name" do
      expect { scene_at(0).beat_frame(:nope) }.to raise_error(AnimateIt::Error, /Unknown beat/)
    end
  end

  describe "#beat_end" do
    it "returns start_frame + duration_frames" do
      expect(scene_at(0).beat_end(:outro)).to eq(80)
      expect(scene_at(0).beat_end(:intro)).to eq(30)
    end
  end

  describe "#beat_range" do
    it "returns [start_frame, end_frame] as a two-element array" do
      expect(scene_at(0).beat_range(:outro)).to eq([60, 80])
    end

    it "destructures cleanly via parallel assignment" do
      start_frame, end_frame = scene_at(0).beat_range(:intro)
      expect(start_frame).to eq(0)
      expect(end_frame).to eq(30)
    end
  end
end
