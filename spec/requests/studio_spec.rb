require "rails_helper"

# Exercises the mounted engine end-to-end through real HTTP: the Studio index,
# a single frame, and the filmstrip page the renderer screenshots. Proves the
# `/animate_it` mount, the app/videos view-path lookup, and HAML sidecar
# rendering all work in a host app that only installs the gem.
RSpec.describe "AnimateIt Studio", type: :request do
  let(:mount) { AnimateIt.config.mount_path }

  it "mounts the studio at /animate_it" do
    expect(mount).to eq("/animate_it")

    get mount

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dummy-motion")
  end

  it "renders a single frame of the fixture composition" do
    get "#{mount}/compositions/dummy-motion/frame/7"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dm-box")
  end

  it "renders the filmstrip the renderer captures" do
    get "#{mount}/compositions/dummy-motion/filmstrip"

    expect(response).to have_http_status(:ok)
    # Filmstrip drives frame visibility via the injected controller script.
    expect(response.body).to include("__animateIt")
  end

  it "404s for an unknown composition" do
    get "#{mount}/compositions/does-not-exist/frame/0"

    expect(response).to have_http_status(:not_found)
  end

  context "when the engine is mounted in production" do
    before do
      allow(Rails.env).to receive(:local?).and_return(false)
    end

    it "exposes only explicitly public client players" do
      get "#{mount}/compositions/client-runtime-spec/player"
      expect(response).to have_http_status(:not_found)

      get "#{mount}/public/compositions/dummy-motion/player"
      expect(response).to have_http_status(:not_found)

      get "#{mount}/public/compositions/client-runtime-spec/player"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css('script[data-animate-it-transport="true"]')).to be_present
      expect(response.parsed_body.at_css("[data-animate-it-play]")).to be_present
      expect(response.body).to include("/public/compositions/client-runtime-spec/audio/0")
    end

    it "serves byte ranges only for an allowlisted composition's declared audio" do
      path = Rails.root.join("app/audio/spec/client-runtime.wav")
      original = path.binread if path.file?
      FileUtils.mkdir_p(path.dirname)
      path.binwrite("public-player-audio")

      get "#{mount}/public/compositions/client-runtime-spec/audio/0", headers: { "Range" => "bytes=0-3" }

      expect(response).to have_http_status(:partial_content)
      expect(response.headers["Accept-Ranges"]).to eq("bytes")
      expect(response.body).to eq("publ")
    ensure
      original ? path.binwrite(original) : FileUtils.rm_f(path)
    end
  end
end
