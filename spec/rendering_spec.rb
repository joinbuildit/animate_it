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
  end

  after(:all) do
    @server&.stop
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
end
