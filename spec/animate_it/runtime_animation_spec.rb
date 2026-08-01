require "rails_helper"
require "open3"

RSpec.describe AnimateIt::Runtime do
  let(:runtime_path) { AnimateIt::Engine.root.join("lib/animate_it/runtime/runtime.js").to_s }

  def run_node(script)
    stdout, stderr, status = Open3.capture3("node", "-e", script, runtime_path)
    raise "node failed: #{stderr}" unless status.success?

    JSON.parse(stdout)
  end

  it "pauses and deterministically seeks native animations" do
    result = run_node(<<~JS)
      const api = require(process.argv[1]);
      const animation = () => ({
        currentTime: null, pauseCalls: 0, playState: "running",
        pause() { this.pauseCalls += 1; this.playState = "paused"; }
      });
      const finite = animation();
      const infinite = animation();
      let lookups = 0;
      const root = {
        querySelectorAll() { return []; },
        getAnimations(options) {
          if (!options.subtree) throw new Error("subtree animation lookup is required");
          lookups += 1;
          return lookups === 1 ? [finite, infinite] : [infinite];
        }
      };
      const player = api.createPlayer(
        { duration: 90, fps: 30, groups: {}, texts: {}, layers: [] }, root
      );
      player.setFrame(60);
      player.setFrame(15);
      player.setFrame(15);
      process.stdout.write(JSON.stringify({
        finiteTime: finite.currentTime, finitePauses: finite.pauseCalls,
        infiniteTime: infinite.currentTime, infinitePauses: infinite.pauseCalls,
        frame: player.currentFrame()
      }));
    JS

    expect(result).to eq(
      "finiteTime" => 500,
      "finitePauses" => 3,
      "infiniteTime" => 500,
      "infinitePauses" => 3,
      "frame" => 15
    )
  end

  it "uses explicit v2 selectors to isolate segment bindings" do
    result = run_node(<<~JS)
      const api = require(process.argv[1]);
      const values = {};
      const element = (key) => ({ style: { setProperty(name, value) { values[key + name] = value; } } });
      const first = element("first");
      const second = element("second");
      const counter = { textContent: "" };
      const selectors = [];
      const root = {
        querySelectorAll(selector) {
          selectors.push(selector);
          if (selector === '#first [data-animate-vars="root"]') return [first];
          if (selector === '#second [data-animate-vars="root"]') return [second];
          if (selector === '#first [data-animate-text="counter"]') return [counter];
          return [];
        }
      };
      const rle = (value) => ({ t: "rle", r: [[value, 1]] });
      const player = api.createPlayer({
        duration: 1, fps: 30, layers: [],
        groups: { "s0:root": { "--op": rle("0.25") }, "s1:root": { "--op": rle("0.75") } },
        groupSelectors: {
          "s0:root": '#first [data-animate-vars="root"]',
          "s1:root": '#second [data-animate-vars="root"]'
        },
        texts: { "s0:counter": rle("first") },
        textSelectors: { "s0:counter": '#first [data-animate-text="counter"]' }
      }, root);
      player.setFrame(0);
      process.stdout.write(JSON.stringify({ selectors, values, text: counter.textContent }));
    JS

    expect(result.fetch("selectors")).to eq(
      ['#first [data-animate-vars="root"]', '#second [data-animate-vars="root"]',
       '#first [data-animate-text="counter"]']
    )
    expect(result.fetch("values")).to eq("first--op" => "0.25", "second--op" => "0.75")
    expect(result.fetch("text")).to eq("first")
  end

  it "seeks native animations against each scene segment's local clock" do
    result = run_node(<<~JS)
      const api = require(process.argv[1]);
      const animation = () => ({ currentTime: null, playState: "running", pause() { this.playState = "paused"; } });
      const firstAnimation = animation();
      const delayedAnimation = animation();
      const layer = (animation) => ({ classList: { toggle() {} }, getAnimations() { return [animation]; } });
      const root = {
        querySelectorAll(selector) {
          if (selector === "#first") return [layer(firstAnimation)];
          if (selector === "#delayed") return [layer(delayedAnimation)];
          return [];
        }
      };
      const player = api.createPlayer({
        duration: 120, fps: 30, groups: {}, texts: {},
        layers: [
          { sel: "#first", from: 0, to: 120, origin: 0 },
          { sel: "#delayed", from: 60, to: 120, origin: 60 }
        ]
      }, root);
      player.setFrame(75);
      process.stdout.write(JSON.stringify({ first: firstAnimation.currentTime, delayed: delayedAnimation.currentTime }));
    JS

    expect(result).to eq("first" => 2500, "delayed" => 500)
  end

  it "removes CSS variables when an RLE track contains an unset value" do
    result = run_node(<<~JS)
      const api = require(process.argv[1]);
      const calls = [];
      const element = { style: {
        setProperty(name, value) { calls.push(["set", name, value]); },
        removeProperty(name) { calls.push(["remove", name]); }
      } };
      const root = {
        querySelectorAll(selector) { return selector === '[data-animate-vars="root"]' ? [element] : []; },
        getAnimations() { return []; }
      };
      const player = api.createPlayer({
        duration: 4, fps: 30, texts: {}, layers: [],
        groups: { root: { "--optional": { t: "rle", r: [[null, 1], ["visible", 1], [null, 1], ["again", 1]] } } }
      }, root);
      [0, 1, 2, 3].forEach((frame) => player.setFrame(frame));
      process.stdout.write(JSON.stringify(calls));
    JS

    expect(result).to eq(
      [
        ["remove", "--optional"],
        ["set", "--optional", "visible"],
        ["remove", "--optional"],
        ["set", "--optional", "again"]
      ]
    )
  end

  it "owns a frame clock and synchronizes declared audio" do
    result = run_node(<<~JS)
      const api = require(process.argv[1]);
      let now = 0;
      let nextTick = null;
      global.performance = { now: () => now };
      global.requestAnimationFrame = (callback) => { nextTick = callback; return 1; };
      global.cancelAnimationFrame = () => { nextTick = null; };

      let current = 0;
      const frames = [];
      const player = {
        duration: 5, fps: 10,
        currentFrame: () => current,
        setFrame(frame) { current = frame; frames.push(frame); return frame; }
      };
      const audio = {
        dataset: { fromFrame: "0", durationFrames: "5", gain: "0.5", loop: "false" },
        duration: 2, currentTime: 0, readyState: 1, paused: true, playCalls: 0,
        play() { this.paused = false; this.playCalls += 1; return Promise.resolve(); },
        pause() { this.paused = true; },
        addEventListener() {}
      };
      const button = {
        textContent: "", attrs: {},
        setAttribute(name, value) { this.attrs[name] = value; },
        addEventListener(_name, callback) { this.click = callback; }
      };

      (async () => {
        const transport = api.createTransport(player, [audio], { loop: false, button });
        await transport.play();
        now = 220;
        nextTick(now);
        transport.pause();
        process.stdout.write(JSON.stringify({
          frames, frame: transport.currentFrame(), playing: transport.playing(),
          playCalls: audio.playCalls, audioTime: audio.currentTime, volume: audio.volume,
          button: button.textContent, pressed: button.attrs["aria-pressed"]
        }));
      })();
    JS

    expect(result).to eq(
      "frames" => [2], "frame" => 2, "playing" => false,
      "playCalls" => 1, "audioTime" => 0.2, "volume" => 0.5,
      "button" => "Play", "pressed" => "false"
    )
  end
end
