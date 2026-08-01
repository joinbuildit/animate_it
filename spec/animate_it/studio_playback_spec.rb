require "rails_helper"
require "open3"

RSpec.describe "AnimateIt Studio playback clock" do
  let(:script_path) do
    AnimateIt::Engine.root.join("app/views/animate_it/studio/_studio_script.html.haml").to_s
  end

  it "rounds frame inputs and derives playback from elapsed time" do
    harness = <<~JS
      const fs = require("fs");
      const template = fs.readFileSync(process.argv[1], "utf8").split("\\n");
      const source = template.slice(1).map((line) => line.startsWith("  ") ? line.slice(2) : line).join("\\n");
      const listeners = {};
      const frames = [];
      let animationCallback = null;
      let animationId = 0;

      const element = (extra = {}) => Object.assign({
        value: "0", textContent: "", dataset: {}, style: {},
        addEventListener(type, callback) { this.listeners[type] = callback; },
        listeners: {}
      }, extra);

      const studio = element({ dataset: {
        frameBaseUrl: "/animate_it/frame", playerUrl: "/animate_it/player",
        clientDriven: "true", duration: "20", fps: "10"
      } });
      const iframe = element({ contentWindow: { __animateIt: { setFrame(frame) { frames.push(frame); } } } });
      const scrubber = element();
      const frameInput = element();
      const frameLabel = element();
      const playButton = element();
      const speedInput = element({ value: "1" });
      const elements = {
        animate_it_frame: iframe, animate_it_scrubber: scrubber,
        animate_it_frame_input: frameInput, animate_it_frame_label: frameLabel,
        animate_it_play: playButton, animate_it_speed: speedInput,
        animate_it_props_json: null
      };
      const document = {
        querySelector(selector) { return selector === ".animate-it-studio" ? studio : null; },
        querySelectorAll() { return []; },
        getElementById(id) { return elements[id]; },
        addEventListener(type, callback) { listeners[type] = callback; }
      };
      const window = {
        location: { href: "http://example.test/animate_it?frame=1.6", search: "?frame=1.6" },
        history: { state: null, replaceState() {} },
        performance: { now() { return 0; } },
        requestAnimationFrame(callback) { animationCallback = callback; animationId += 1; return animationId; },
        cancelAnimationFrame() {},
        addEventListener(type, callback) { listeners[type] = callback; }
      };
      global.document = document;
      global.window = window;

      eval(source);
      playButton.listeners.click();
      animationCallback(250);

      process.stdout.write(JSON.stringify({
        frames, currentFrame: window.AnimateItStudio.currentFrame(), label: frameLabel.textContent
      }));
    JS

    stdout, stderr, status = Open3.capture3("node", "-e", harness, script_path)
    raise "node failed: #{stderr}" unless status.success?

    expect(JSON.parse(stdout)).to eq("frames" => [2, 4], "currentFrame" => 4, "label" => 4)
  end
end
