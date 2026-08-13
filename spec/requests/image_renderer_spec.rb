require "rails_helper"

RSpec.describe "AnimateIt image rendering", type: :request do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:capturer) { instance_double("capturer", version: "test-browser", capture_frame: "png-bytes") }

  around do |example|
    previous = AnimateIt.config.internal_rendering
    AnimateIt.config.internal_rendering = true
    example.run
  ensure
    AnimateIt.config.internal_rendering = previous
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    allow(AnimateIt::FrameCapturers).to receive(:build).and_return(capturer)
  end

  it "returns an inline PNG and reuses its cached bytes" do
    allow(AnimateIt::RenderTicketStore).to receive(:delete).and_call_original
    get "/render-image-spec"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Content-Disposition"]).to eq("inline")
    expect(response.body).to eq("png-bytes")
    expect(AnimateIt::RenderTicketStore).to have_received(:delete).with(kind_of(String))
    etag = response.headers.fetch("ETag")

    get "/render-image-spec", headers: { "If-None-Match" => etag }

    expect(response).to have_http_status(:not_modified)
    expect(capturer).to have_received(:capture_frame).once
  end

  it "serves opaque render tickets only while internal rendering is enabled" do
    ticket = AnimateIt::RenderTicketStore.create!(composition: ClientRuntimeSpecVideo, props: {})

    get "#{AnimateIt.config.mount_path}/internal/render_pages/#{ticket}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css("script[data-animate-it-manifest]")).to be_present

    # Auto fallback may load the same ticket in Servo and then Playwright.
    get "#{AnimateIt.config.mount_path}/internal/render_pages/#{ticket}"
    expect(response).to have_http_status(:ok)

    AnimateIt::RenderTicketStore.delete(ticket)
    get "#{AnimateIt.config.mount_path}/internal/render_pages/#{ticket}"
    expect(response).to have_http_status(:not_found)

    AnimateIt.config.internal_rendering = false
    get "#{AnimateIt.config.mount_path}/internal/render_pages/#{ticket}"
    expect(response).to have_http_status(:not_found)
  end

  it "fails early when Rails cache cannot retain render tickets" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)

    expect { AnimateIt::RenderTicketStore.create!(composition: ClientRuntimeSpecVideo, props: {}) }
      .to raise_error(AnimateIt::Error, /shared, writable Rails cache/)
  end
end
