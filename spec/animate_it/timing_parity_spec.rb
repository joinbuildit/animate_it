require "rails_helper"
require "open3"

RSpec.describe "Ruby and client-runtime timing parity" do
  let(:runtime_path) { AnimateIt::Engine.root.join("lib/animate_it/runtime/runtime.js").to_s }
  let(:cases) do
    [
      { frames: [0, 10], values: [0, 1], easing: "ease_out", unit: "", samples: [-5, 0, 1, 5, 9, 10, 15] },
      { frames: [0, 10], values: [16, 0], easing: "ease_out", unit: "px", samples: [-1, 0, 2, 5, 8, 10, 40] },
      { frames: [4, 12], values: [0, 1], easing: "linear", unit: "", samples: [0, 4, 5, 11, 12, 30] },
      { frames: [10, 20, 30], values: [-40, 25, -3.5], easing: "ease_in", unit: "%", samples: [5, 10, 13, 20, 26, 30] },
      { frames: [0, 44], values: [0.15, 0.85], easing: "ease_in_out", unit: "", samples: [0, 11, 22, 33, 44] }
    ]
  end

  def ruby_value(test_case, frame)
    value = AnimateIt::Timing.interpolate(
      frame,
      test_case.fetch(:frames),
      test_case.fetch(:values),
      easing: test_case.fetch(:easing).to_sym,
      extrapolate_left: :clamp,
      extrapolate_right: :clamp
    ).round(4)
    "#{value}#{test_case.fetch(:unit)}"
  end

  it "produces byte-identical keyframe values in Ruby and JavaScript" do
    script = <<~JS
      const api = require(process.argv[1]);
      const cases = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const results = cases.map((c) => {
        const track = { t: "kf", k: c.frames.map((frame, i) => [frame, c.values[i]]), e: c.easing, u: c.unit };
        const compiled = api.compileTrack(track);
        return c.samples.map((frame) => compiled.valueAt(frame));
      });
      process.stdout.write(JSON.stringify(results));
    JS
    stdout, stderr, status = Open3.capture3(
      "node", "-e", script, runtime_path, stdin_data: JSON.generate(cases)
    )

    expect(status).to be_success, "node failed: #{stderr}"
    results = JSON.parse(stdout)
    cases.each_with_index do |test_case, case_index|
      test_case.fetch(:samples).each_with_index do |frame, sample_index|
        expect(results.dig(case_index, sample_index)).to eq(ruby_value(test_case, frame))
      end
    end
  end
end
