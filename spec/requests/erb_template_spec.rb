require "rails_helper"

# Proves scene sidecar templates work in ERB as well as HAML. `dummy-erb` is an
# exact twin of the HAML `dummy-motion` fixture whose only difference is an ERB
# canvas (canvas.html.erb). Both resolve through the same extensionless
# `render_scene_template("canvas")` path, so a green run here means an app can
# mix HAML and ERB scenes freely — and, via the CI matrix, that it holds on both
# Rails 7.2 and 8.1.
RSpec.describe "AnimateIt ERB scene templates", type: :request do
  let(:mount) { AnimateIt.config.mount_path }

  it "lists the ERB composition in the studio" do
    get mount

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dummy-erb")
  end

  it "renders a frame from the ERB canvas" do
    get "#{mount}/compositions/dummy-erb/frame/7"

    expect(response).to have_http_status(:ok)
    # The ERB canvas emits the same markup the HAML twin does: the .dm-box
    # element and the per-frame CSS-variable bag on .dm-root.
    expect(response.body).to include("dm-box")
    expect(response.body).to include('class="dm-root"')
    expect(response.body).to include("--box-x")
  end
end
