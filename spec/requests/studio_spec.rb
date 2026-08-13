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

  it "marks client-driven compositions for the persistent Studio player" do
    get "#{mount}/compositions/client-runtime-spec"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css(".animate-it-studio")["data-client-driven"]).to eq("true")
    expect(response.parsed_body.at_css("#animate_it_frame")["src"]).to end_with("/player?pp=disable")
  end

  it "404s for an unknown composition" do
    get "#{mount}/compositions/does-not-exist/frame/0"

    expect(response).to have_http_status(:not_found)
  end

  it "renders headless embed builders from ERB and HAML host views" do
    get "/embed-headless-erb"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css(".product-demo-card").size).to eq(3)
    expect(response.parsed_body.at_css(".animate-it-chapters--pills")).to be_nil

    get "/embed-headless-haml"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css(".product-demo-timeline__step").size).to eq(3)
    expect(response.parsed_body.at_css(".animate-it-chapters--pills")).to be_nil
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
      expect(response.headers["X-Frame-Options"]).to eq("SAMEORIGIN")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(response.headers["Set-Cookie"]).to be_nil
      expect(response.parsed_body.at_css('script[data-animate-it-transport="true"]')).to be_present
      manifest = JSON.parse(response.parsed_body.at_css("script[data-animate-it-manifest]").text)
      expect(manifest.fetch("chapters").map { |chapter| chapter.fetch("name") }).to eq(%w[intro details finish])
      expect(response.parsed_body.at_css("[data-animate-it-play]")).to be_present
      expect(response.body).to include("/public/compositions/client-runtime-spec/audio/0")

      get "#{mount}/public/compositions/client-runtime-spec/player",
          params: { props_json: { headline: "private-session-data" }.to_json }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("private-session-data")
    end

    it "keeps every development and render surface unavailable" do
      get mount
      expect(response).to have_http_status(:not_found)

      get "#{mount}/compositions/client-runtime-spec"
      expect(response).to have_http_status(:not_found)

      get "#{mount}/compositions/client-runtime-spec/frame/0"
      expect(response).to have_http_status(:not_found)

      get "#{mount}/compositions/client-runtime-spec/filmstrip"
      expect(response).to have_http_status(:not_found)

      get "#{mount}/compositions/client-runtime-spec/player"
      expect(response).to have_http_status(:not_found)

      patch "#{mount}/compositions/client-runtime-spec/props", params: { props_json: "{}" }
      expect(response).to have_http_status(:not_found)

      post "#{mount}/compositions/client-runtime-spec/renders"
      expect(response).to have_http_status(:not_found)

      get "#{mount}/renders/not-a-render"
      expect(response).to have_http_status(:not_found)
    end

    it "hides canvas navigation only when the decorative embed provides host controls" do
      get "#{mount}/public/compositions/client-runtime-spec/player",
          params: { embedded: "1", host_navigation: "1" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css("html")["data-animate-it-embedded"]).to eq("true")
      expect(response.parsed_body.at_css("html")["data-animate-it-host-navigation"]).to eq("true")
      expect(response.body).to include('html[data-animate-it-embedded="true"] .animate-it-public-play')
      expect(response.body).to include('html[data-animate-it-host-navigation="true"]')

      get "#{mount}/public/compositions/client-runtime-spec/player", params: { embedded: "1" }
      expect(response.parsed_body.at_css("html")["data-animate-it-host-navigation"]).to eq("false")
    end

    it "lets the host embed own autoplay while preserving direct-player options" do
      get "#{mount}/public/compositions/broken-image-spec/player"
      expect(response.parsed_body.at_css("script[data-animate-it-tracks]")["data-animate-it-autoplay"]).to eq("true")

      get "#{mount}/public/compositions/broken-image-spec/player", params: { embedded: "1" }
      expect(response.parsed_body.at_css("script[data-animate-it-tracks]")["data-animate-it-autoplay"]).to eq("false")
    end

    it "serves versioned, immutable embed assets without exposing development tools" do
      get "#{mount}/assets/#{AnimateIt::VERSION}/embed.js"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/javascript")
      expect(response.headers["Cache-Control"]).to include("public", "immutable")

      get "#{mount}/assets/#{AnimateIt::VERSION}/embed.css"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/css")
      expect(response.headers["Cache-Control"]).to include("public", "immutable")

      get "#{mount}/assets/wrong/embed.js"
      expect(response).to have_http_status(:not_found)
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
