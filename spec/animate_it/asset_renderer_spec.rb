require "rails_helper"

RSpec.describe AnimateIt::AssetRenderer do
  let(:output_root) { Rails.root.join("tmp/asset-renderer-spec") }
  let(:composition) do
    Class.new(AnimateIt::Composition) do
      id "asset-renderer-shared-capture"
      fps 10
      duration 1.second

      outputs do
        mp4 to: "tmp/asset-renderer-spec/output.mp4"
        webm to: "tmp/asset-renderer-spec/output.webm"
        png frame: 3, to: "tmp/asset-renderer-spec/poster-a.png"
        gif to: "tmp/asset-renderer-spec/output.gif"
        png frame: 3, to: "tmp/asset-renderer-spec/poster-b.png"
      end
    end
  end

  after { FileUtils.rm_rf(output_root) }

  it "captures once per distinct frame range while preserving output order" do
    render_calls = []
    allow(AnimateIt::VideoRenderer).to receive(:new) do |**initialization|
      instance_double(AnimateIt::VideoRenderer).tap do |renderer|
        allow(renderer).to receive(:render) do |**options|
          render_calls << { initialization:, options: }
        end
      end
    end

    written = described_class.render_composition(composition, host: "http://example.test")

    expect(written.map(&:basename).map(&:to_s)).to eq(
      %w[output.mp4 output.webm poster-a.png output.gif poster-b.png]
    )
    expect(render_calls.count { |call| !call.dig(:options, :reuse_captured_frames) }).to eq(2)
    expect(render_calls.count { |call| call.dig(:options, :reuse_captured_frames) }).to eq(3)

    animated = render_calls.values_at(0, 1, 3)
    posters = render_calls.values_at(2, 4)
    expect(animated.map { |call| call.dig(:initialization, :frames_dir) }.uniq.size).to eq(1)
    expect(posters.map { |call| call.dig(:initialization, :frames_dir) }.uniq.size).to eq(1)
    expect(animated.first.dig(:initialization, :frames_dir)).not_to eq(
      posters.first.dig(:initialization, :frames_dir)
    )
  end

  it "does not capture or encode a still outside the requested range" do
    allow(AnimateIt::VideoRenderer).to receive(:new) do
      instance_double(AnimateIt::VideoRenderer, render: nil)
    end

    written = described_class.render_composition(
      composition,
      host: "http://example.test",
      frame_range: 5..8
    )

    expect(written.values_at(2, 4)).to eq([nil, nil])
    expect(AnimateIt::VideoRenderer).to have_received(:new).exactly(3).times
  end
end
