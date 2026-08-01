require "rails_helper"
require "net/http"
require "socket"

# End-to-end render smoke test: boots a real Puma server for the dummy app,
# then drives the full VideoRenderer pipeline (Playwright frame capture →
# FFmpeg encode) to prove the gem produces a non-empty MP4 in a host app that
# only installs it. Heavy (needs Chromium + ffmpeg), so it is opt-in:
#
#   RUN_RENDER_SMOKE=1 bundle exec rspec spec/rendering_spec.rb
#
# CI sets RUN_RENDER_SMOKE=1 after installing ffmpeg + the Playwright browser.
RSpec.describe "AnimateIt render pipeline", :render_smoke, type: :request do
  before(:all) do
    skip "set RUN_RENDER_SMOKE=1 (needs ffmpeg + Playwright chromium)" unless ENV["RUN_RENDER_SMOKE"] == "1"

    @port = find_free_port
    @server = boot_server(@port)
    wait_until_up("http://127.0.0.1:#{@port}#{AnimateIt.config.mount_path}")
    @audio_path = Rails.root.join("app/audio/spec/client-runtime.wav")
    write_wav(@audio_path, duration: 1.0, frequency: 440)
  end

  after(:all) do
    @server&.stop
    FileUtils.rm_f(@audio_path) if @audio_path
    FileUtils.rm_rf(@audio_path.dirname) if @audio_path&.dirname&.directory? && @audio_path.dirname.empty?
  rescue StandardError
    nil
  end

  it "renders the fixture composition to a non-empty MP4" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, "dummy-motion.mp4")
      AnimateIt.load_compositions!
      composition = AnimateIt.registry.fetch("dummy-motion")

      result = AnimateIt::VideoRenderer.new(
        composition: composition,
        host: "http://127.0.0.1:#{@port}",
        output_path: output_path
      ).render

      expect(File).to exist(result)
      expect(File.size(result)).to be > 0
    end
  end

  it "seeks one Chromium-rendered template with filmstrip parity and no frame requests" do
    require "playwright"
    AnimateIt.load_compositions!
    composition = AnimateIt.registry.fetch("client-runtime-spec")
    composition::Scene.reset_render_count!
    requests = []

    with_browser do |context|
      player = context.new_page
      player.on("request", ->(request) { requests << request.url })
      open_runtime_page(player, composition, "player")

      expect(composition::Scene.render_count).to eq(composition.structure_layers.size)

      filmstrip = context.new_page
      open_runtime_page(filmstrip, composition, "filmstrip")
      begin
        Dir.mktmpdir("animate-it-runtime-parity") do |dir|
          verifier = AnimateIt::Verification.new(
            composition: composition,
            host: server_host,
            output_dir: dir,
            threshold: 50,
            alpha_threshold: 50
          )

          [2, 4, 5, 6, 9, 10, 11, 13, 11, 5, 5].each do |frame|
            expect(runtime_state(player, frame, ".animate-it-layer.is-active"))
              .to eq(runtime_state(filmstrip, frame, ".animate-it-frame.is-active"))

            player_shot = Pathname(dir).join("player-#{frame}.png")
            filmstrip_shot = Pathname(dir).join("filmstrip-#{frame}.png")
            player.screenshot(path: player_shot.to_s, omitBackground: true)
            filmstrip.screenshot(path: filmstrip_shot.to_s, omitBackground: true)
            rgb_psnr, alpha_psnr = verifier.send(:psnr_between, filmstrip_shot, player_shot)
            expect(rgb_psnr).to be >= 50
            expect(alpha_psnr).to be >= 50
          end
        end
      ensure
        filmstrip.close
      end

      expected_renders = composition.structure_layers.size + filmstrip_render_count(composition)
      expect(composition::Scene.render_count).to eq(expected_renders)
    end

    expect(requests.grep(%r{/client-runtime-spec/player}).size).to eq(1)
    expect(requests.grep(%r{/client-runtime-spec/frame/})).to be_empty
  end

  it "serves Chromium-seekable audio ranges and aligns Studio audio seeks" do
    require "playwright"
    AnimateIt.load_compositions!
    composition = AnimateIt.registry.fetch("client-runtime-spec")

    with_browser do |context|
      studio = context.new_page
      response = studio.goto(
        "#{server_host}#{AnimateIt.config.mount_path}/compositions/#{composition.id}",
        waitUntil: "networkidle"
      )
      expect(response).to be_ok
      studio.wait_for_function("window.AnimateItStudio !== undefined")
      studio.wait_for_function(
        "Array.from(document.querySelectorAll('audio')).every((el) => el.readyState >= 1)"
      )

      range = studio.evaluate(<<~JS)
        async () => {
          const response = await fetch(
            "#{AnimateIt.config.mount_path}/compositions/client-runtime-spec/audio/0",
            { headers: { Range: "bytes=0-31" } }
          );
          return {
            status: response.status,
            acceptRanges: response.headers.get("accept-ranges"),
            contentRange: response.headers.get("content-range"),
            bytes: (await response.arrayBuffer()).byteLength
          };
        }
      JS
      expect(range).to include("status" => 206, "acceptRanges" => "bytes", "bytes" => 32)
      expect(range.fetch("contentRange")).to match(%r{\Abytes 0-31/\d+\z})

      audio_state = studio.evaluate(<<~JS)
        () => {
          window.AnimateItStudio.setFrame(9);
          return Array.from(document.querySelectorAll("audio[data-from-frame]")).map((el) => ({
            loop: el.dataset.loop,
            from: Number(el.dataset.fromFrame),
            duration: el.duration,
            currentTime: el.currentTime,
            paused: el.paused
          }));
        }
      JS
      loop_audio = audio_state.find { |audio| audio.fetch("loop") == "true" }
      voice_audio = audio_state.find { |audio| audio.fetch("loop") == "false" }

      expect(loop_audio.fetch("currentTime")).to be_within(0.08).of(0.9 % loop_audio.fetch("duration"))
      expect(voice_audio.fetch("currentTime")).to be_within(0.08).of(0.3)
      expect(audio_state).to all(include("paused" => true))

      studio.locator("#animate_it_play").click
      studio.wait_for_function(<<~JS)
        (() => {
          const voice = Array.from(document.querySelectorAll("audio[data-from-frame]"))
            .find((el) => el.dataset.loop === "false");
          return voice && !voice.paused && voice.currentTime > 0.34;
        })()
      JS
      playing_state = studio.evaluate(<<~JS)
        () => Array.from(document.querySelectorAll("audio[data-from-frame]")).map((el) => ({
          loop: el.dataset.loop,
          currentTime: el.currentTime,
          paused: el.paused
        }))
      JS
      expect(playing_state).to include(include("paused" => false))
      expect(playing_state.find { |audio| audio.fetch("loop") == "false" }.fetch("currentTime")).to be > 0.3

      studio.locator("#animate_it_play").click
    end

    Dir.mktmpdir("animate-it-client-audio-render") do |directory|
      output = Pathname(directory).join("client-runtime.mp4")
      AnimateIt::VideoRenderer.new(
        composition: composition,
        host: server_host,
        output_path: output,
        frames_dir: Pathname(directory).join("frames"),
        format: :mp4
      ).render

      expect(ffprobe_stream_types(output)).to contain_exactly("video", "audio")
    end
  end

  it "plays an allowlisted public composition without a Studio parent" do
    require "playwright"
    AnimateIt.load_compositions!
    composition = AnimateIt.registry.fetch("client-runtime-spec")

    with_browser do |context|
      player = context.new_page
      response = player.goto(
        "#{server_host}#{AnimateIt.config.mount_path}/public/compositions/#{composition.id}/player",
        waitUntil: "networkidle"
      )

      expect(response).to be_ok
      player.wait_for_function("window.AnimateItTransport !== undefined")
      expect(player.evaluate("window.AnimateItTransport.playing()")).to be(false)

      player.locator("[data-animate-it-play]").click
      player.wait_for_function("window.AnimateItTransport.currentFrame() > 0")

      state = player.evaluate(<<~JS)
        () => ({
          playing: window.AnimateItTransport.playing(),
          frame: window.AnimateItTransport.currentFrame(),
          audible: Array.from(document.querySelectorAll("audio")).some((audio) => !audio.paused),
          button: document.querySelector("[data-animate-it-play]").textContent
        })
      JS
      expect(state).to include("playing" => true, "audible" => true, "button" => "Pause")
      expect(state.fetch("frame")).to be > 0
    end
  end

  # --- helpers -------------------------------------------------------------

  def find_free_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end

  def boot_server(port)
    require "puma"
    require "puma/server"
    server = Puma::Server.new(Rails.application)
    server.add_tcp_listener("127.0.0.1", port)
    server.run
    server
  end

  def wait_until_up(url, timeout: 30)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      Net::HTTP.get_response(URI(url))
      return
    rescue StandardError
      raise "server did not start within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.3
    end
  end

  def server_host
    "http://127.0.0.1:#{@port}"
  end

  def with_browser
    cli = ENV.fetch("PLAYWRIGHT_CLI_EXECUTABLE_PATH", "npx playwright")
    Playwright.create(playwright_cli_executable_path: cli) do |playwright|
      browser = playwright.chromium.launch(headless: true)
      begin
        context = browser.new_context(viewport: { width: 240, height: 120 })
        yield context
      ensure
        browser.close
      end
    end
  end

  def open_runtime_page(page, composition, endpoint)
    response = page.goto(
      "#{server_host}#{AnimateIt.config.mount_path}/compositions/#{composition.id}/#{endpoint}?pp=disable",
      waitUntil: "networkidle"
    )
    expect(response).to be_ok
    page.wait_for_function('document.documentElement.dataset.animateItReady === "1"')
  end

  def runtime_state(page, frame, active_selector)
    page.evaluate("(value) => window.__animateIt.setFrame(value)", arg: frame)
    page.evaluate("() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))")
    page.evaluate(
      <<~JS,
        (activeSelector) => Array.from(
          document.querySelectorAll(`${activeSelector} .runtime-spec-scene`)
        ).map((scene) => {
          const root = scene.querySelector('[data-animate-vars="root"]');
          const badge = scene.querySelector('[data-anim="badge"]');
          const probe = scene.querySelector('[data-css-animation-probe]');
          const firstWord = scene.querySelector('[data-animate-vars^="textfx-"] span');
          return {
            name: scene.dataset.sceneName,
            x: root.style.getPropertyValue("--local-x"),
            opacity: root.style.getPropertyValue("--local-opacity"),
            text: scene.querySelector('[data-animate-text="counter"]').textContent,
            badgeOpacity: getComputedStyle(badge).opacity,
            badgeTransform: getComputedStyle(badge).transform,
            probeOpacity: getComputedStyle(probe).opacity,
            wordOpacity: getComputedStyle(firstWord).opacity
          };
        }).sort((a, b) => a.name.localeCompare(b.name))
      JS
      arg: active_selector
    )
  end

  def filmstrip_render_count(composition)
    (0...composition.duration_in_frames).sum do |frame|
      composition.timeline.active_segments(frame, kind: :scene).size
    end
  end

  def write_wav(path, duration:, frequency:)
    sample_rate = 8_000
    samples = (sample_rate * duration).to_i.times.map do |index|
      (Math.sin(2 * Math::PI * frequency * index / sample_rate) * 8_000).round
    end
    data = samples.pack("s<*")
    header = [
      "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, sample_rate,
      sample_rate * 2, 2, 16, "data", data.bytesize
    ].pack("A4VA4A4VvvVVvvA4V")

    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, header + data)
  end

  def ffprobe_stream_types(path)
    stdout, stderr, status = Open3.capture3(
      "ffprobe", "-v", "error", "-show_entries", "stream=codec_type", "-of", "json", path.to_s
    )
    raise "ffprobe failed: #{stderr}" unless status.success?

    JSON.parse(stdout).fetch("streams").map { |stream| stream.fetch("codec_type") }
  end
end
