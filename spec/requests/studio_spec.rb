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
end
