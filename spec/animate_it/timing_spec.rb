require "rails_helper"

RSpec.describe AnimateIt::Timing do
  describe ".interpolate" do
    it "maps one range to another" do
      expect(described_class.interpolate(15, [0, 30], [0, 1])).to eq(0.5)
    end

    it "clamps values outside the range" do
      value = described_class.interpolate(45, [0, 30], [0, 1], extrapolate_right: :clamp)

      expect(value).to eq(1)
    end

    it "applies easing" do
      value = described_class.interpolate(15, [0, 30], [0, 1], easing: :ease_in)

      expect(value).to eq(0.25)
    end
  end

  describe ".spring" do
    it "returns a deterministic value for a frame" do
      first = described_class.spring(frame: 10, fps: 30)
      second = described_class.spring(frame: 10, fps: 30)

      expect(first).to eq(second)
    end
  end
end
