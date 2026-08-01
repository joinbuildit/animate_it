require "rails_helper"

RSpec.describe AnimateIt::EmbedHelper, type: :helper do
  before do
    AnimateIt.register(ClientRuntimeSpecVideo)
    AnimateIt.register(DummyMotionVideo)
  end

  it "builds a responsive iframe for an allowlisted composition" do
    html = helper.animate_it_player("client-runtime-spec", title: "Product demo")

    expect(html).to include('src="/animate_it/public/compositions/client-runtime-spec/player"')
    expect(html).to include('title="Product demo"')
    expect(html).to include('allow="autoplay; fullscreen"')
    expect(html).to include("aspect-ratio:240/120")
  end

  it "refuses to embed a composition that has not opted in" do
    expect { helper.animate_it_player("dummy-motion") }
      .to raise_error(ArgumentError, /not public/)
  end
end
