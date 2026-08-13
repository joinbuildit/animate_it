require "rails_helper"
require "playwright"

RSpec.describe AnimateIt::Verification do
  subject(:verification) do
    described_class.new(
      composition: composition,
      host: "http://localhost:3000/",
      output_dir: Rails.root.join("tmp/animate_it/verification-spec"),
      props: { title: "A title", nested: { enabled: true } },
      ready_timeout: 321,
      threshold: 40,
      alpha_threshold: 45
    )
  end

  let(:composition) do
    class_double(
      AnimateIt::Composition,
      id: "test-motion",
      width: 100,
      height: 100,
      duration_in_frames: 10,
      structure_layers: []
    )
  end

  def parsed_props(url)
    query = Rack::Utils.parse_query(url.query)
    expect(query["pp"]).to eq("disable")
    JSON.parse(query.fetch("props_json"))
  end

  describe "page loading" do
    let(:context) { instance_double(Playwright::BrowserContext) }
    let(:page) { instance_double(Playwright::Page) }
    let(:response) { instance_double(Playwright::Response, ok?: true) }

    before do
      allow(context).to receive(:new_page).and_return(page)
      allow(page).to receive(:goto).and_return(response)
      allow(page).to receive(:wait_for_function)
    end

    it "passes identical encoded props to filmstrip and player" do
      urls = []
      allow(page).to receive(:goto) do |url, **_options|
        urls << URI(url)
        response
      end

      verification.send(:open_page, context, "filmstrip")
      verification.send(:open_page, context, "player")

      expect(urls.map(&:path)).to eq(
        %w[/animate_it/compositions/test-motion/filmstrip /animate_it/compositions/test-motion/player]
      )
      urls.each do |url|
        expect(parsed_props(url)).to eq("title" => "A title", "nested" => { "enabled" => true })
      end
    end

    it "bounds navigation and runtime readiness by the configured timeout" do
      verification.send(:open_page, context, "player")

      expect(page).to have_received(:goto).with(kind_of(String), waitUntil: "networkidle", timeout: 321)
      expect(page).to have_received(:wait_for_function).with(
        'document.documentElement.dataset.animateItReady === "1"', timeout: 321
      )
    end

    it "raises a diagnostic error when runtime readiness times out" do
      allow(page).to receive(:wait_for_function)
        .and_raise(Playwright::TimeoutError.new(message: "not ready"))

      expect { verification.send(:open_page, context, "player") }
        .to raise_error(AnimateIt::Error, /Timed out after 321ms.*player.*data-animate-it-ready="1".*not ready/m)
    end

    it "reports unsuccessful responses before waiting for readiness" do
      failed_response = instance_double(
        Playwright::Response, ok?: false, status: 500, status_text: "Internal Server Error"
      )
      allow(page).to receive(:goto).and_return(failed_response)

      expect { verification.send(:open_page, context, "filmstrip") }
        .to raise_error(AnimateIt::Error, /filmstrip.*500 Internal Server Error/)
      expect(page).not_to have_received(:wait_for_function)
    end
  end

  describe "image comparison" do
    def rgba(*pixels)
      pixels.flatten.pack("C*")
    end

    it "ignores RGB beneath fully transparent pixels" do
      rgb_psnr, alpha_psnr = verification.send(
        :psnr_between_rgba,
        rgba([255, 0, 0, 0]),
        rgba([0, 255, 255, 0])
      )

      expect(rgb_psnr).to eq(Float::INFINITY)
      expect(alpha_psnr).to eq(Float::INFINITY)
    end

    it "scores visible RGB and alpha independently" do
      rgb_psnr, alpha_psnr = verification.send(
        :psnr_between_rgba,
        rgba([255, 0, 0, 255], [20, 40, 60, 255]),
        rgba([0, 0, 255, 255], [20, 40, 60, 127])
      )

      expect(rgb_psnr).to be_finite
      expect(alpha_psnr).to be_finite
    end

    it "requires RGB and alpha to meet their thresholds" do
      result = verification.send(:result_for_scores, 7, 50.0, 44.9)

      expect(result).to have_attributes(
        frame: 7, rgb_psnr: 50.0, alpha_psnr: 44.9, passed: false, psnr: 44.9
      )
    end
  end

  describe "screenshots" do
    let(:page) { instance_double(Playwright::Page) }

    before do
      allow(page).to receive(:evaluate)
      allow(page).to receive(:screenshot)
    end

    it "preserves the alpha channel" do
      verification.send(:screenshot, page, 3, "legacy")

      expect(page).to have_received(:screenshot).with(
        path: Rails.root.join("tmp/animate_it/verification-spec/legacy-00003.png").to_s,
        omitBackground: true
      )
    end

    it "re-seeks a player frame after refreshing its active layer" do
      verification.send(:screenshot, page, 3, "player")

      expect(page).to have_received(:evaluate)
        .with("(n) => window.__animateIt.setFrame(n)", arg: 3).twice
    end
  end

  describe "Servo certification" do
    let(:composition) do
      class_double(
        AnimateIt::Composition,
        id: "servo-motion",
        width: 100,
        height: 100,
        duration_in_frames: 10,
        structure_layers: [],
        servo_compatible?: true,
        chapters: instance_double(AnimateIt::Chapters, as_json: [])
      )
    end

    it "handles browser documents without the native animation API" do
      servo_verification = described_class.new(
        composition:,
        host: "http://localhost:3000",
        candidate_backend: :servo
      )
      page = instance_double(Playwright::Page)
      allow(page).to receive(:evaluate).and_return(0)

      expect { servo_verification.send(:ensure_servo_certifiable!, page) }.not_to raise_error
      expect(page).to have_received(:evaluate).with(/typeof document\.getAnimations/)
    end

    it "rejects nondeterministic Servo PNG bytes" do
      servo_verification = described_class.new(
        composition:,
        host: "http://localhost:3000",
        candidate_backend: :servo
      )
      capturer = instance_double(AnimateIt::FrameCapturers::Servo)
      allow(servo_verification).to receive(:servo_capturer).and_return(capturer)
      allow(capturer).to receive(:capture_frame).and_return("same", "same", "changed", "same", "same")

      expect { servo_verification.send(:ensure_servo_deterministic!, 0) }
        .to raise_error(AnimateIt::Error, /different PNG bytes/)
    end
  end
end
