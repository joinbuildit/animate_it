require "rails_helper"

RSpec.describe AnimateIt::PropsSchema do
  subject(:schema) do
    described_class.new.tap do |props|
      props.string :title, default: "Hello"
      props.integer :count, default: 1
      props.number :ratio, default: 0.5
      props.boolean :enabled, default: true
      props.asset :avatar, default: "/avatar.png"
    end
  end

  it "strictly resolves declared render props without changing regular resolution" do
    expect(schema.resolve("unknown" => "accepted")).to include(unknown: "accepted")

    expect(
      schema.resolve_for_render(
        { "title" => "Rendered", "count" => 2, "ratio" => 1.25, "enabled" => false },
        render_origin: "https://example.test"
      )
    ).to include(title: "Rendered", count: 2, ratio: 1.25, enabled: false)
  end

  it "rejects unknown props and incorrect declared scalar types" do
    expect { schema.resolve_for_render("title", render_origin: "https://example.test") }
      .to raise_error(AnimateIt::RenderPropsError, /must be a hash/)
    expect { schema.resolve_for_render({ surprise: true }, render_origin: "https://example.test") }
      .to raise_error(AnimateIt::RenderPropsError, /Unknown render props/)
    expect { schema.resolve_for_render({ count: "2" }, render_origin: "https://example.test") }
      .to raise_error(AnimateIt::RenderPropsError, /count.*integer/)
  end

  it "restricts absolute assets to the render or configured asset origins" do
    expect(
      schema.resolve_for_render(
        { avatar: "https://cdn.example.test/avatar.png" },
        render_origin: "https://example.test",
        asset_origins: ["https://cdn.example.test"]
      )
    ).to include(avatar: "https://cdn.example.test/avatar.png")

    expect do
      schema.resolve_for_render(
        { avatar: "https://untrusted.example/avatar.png" },
        render_origin: "https://example.test"
      )
    end.to raise_error(AnimateIt::RenderPropsError, /allowed origin/)
  end

  it "enforces individual and total serialized size limits" do
    allow(AnimateIt.config).to receive(:render_prop_string_max_bytes).and_return(3)
    expect { schema.resolve_for_render({ title: "four" }, render_origin: "https://example.test") }
      .to raise_error(AnimateIt::RenderPropsError, /title.*exceeds/)

    allow(AnimateIt.config).to receive(:render_prop_string_max_bytes).and_return(100)
    allow(AnimateIt.config).to receive(:render_props_max_bytes).and_return(10)
    expect { schema.resolve_for_render({}, render_origin: "https://example.test") }
      .to raise_error(AnimateIt::RenderPropsError, /Rendered props exceed/)
  end
end
