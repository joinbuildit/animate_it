require "rails_helper"

RSpec.describe AnimateIt::Style do
  describe ".build" do
    it "joins raw rules and keyword properties" do
      style = described_class.build("display: flex", background_color: "red", opacity: nil)

      expect(style).to eq("display: flex; background-color: red")
    end
  end

  describe ".vars" do
    it "formats css custom properties" do
      expect(described_class.vars(tile_opacity: 0.5, tile_y: "12px")).to eq("--tile-opacity: 0.5; --tile-y: 12px")
    end
  end
end
