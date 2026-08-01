require "rails_helper"

RSpec.describe AnimateIt::TrackDocumentSchema do
  let(:document) do
    {
      "v" => 2,
      "fps" => 30,
      "duration" => 90,
      "groups" => { "s0:root" => {} },
      "groupSelectors" => { "s0:root" => '[data-animate-layer="s0/e0"]' },
      "texts" => {},
      "textSelectors" => {},
      "layers" => []
    }
  end

  it "accepts a valid schema-v2 document" do
    expect(described_class.validate!(document)).to eq(document)
  end

  it "keeps generated documents aligned with the current schema" do
    generated = AnimateIt::Tracks::Document.new(fps: 30, duration: 1)

    expect(generated.as_json["v"]).to eq(described_class::CURRENT_VERSION)
    expect { described_class.validate!(generated) }.not_to raise_error
  end

  it "keeps schema-v1 documents compatible" do
    v1 = document.slice("fps", "duration", "groups", "texts", "layers").merge("v" => 1)

    expect { described_class.validate!(v1) }.not_to raise_error
  end

  it "rejects unknown schema versions with supported versions in the error" do
    expect { described_class.validate!(document.merge("v" => 3)) }
      .to raise_error(AnimateIt::Error, /schema 3.*supported versions are 1, 2/)
  end

  it "rejects selectors that reference absent tracks" do
    document["groupSelectors"]["missing"] = "#missing"

    expect { described_class.validate!(document) }
      .to raise_error(AnimateIt::Error, /group selectors reference missing tracks: missing/)
  end
end
