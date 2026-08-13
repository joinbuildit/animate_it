require "rails_helper"

RSpec.describe AnimateIt::FrameCapturers do
  let(:composition) do
    Class.new(AnimateIt::Composition) do
      id "capturer-spec"
      client_driven!
      servo_compatible!
    end
  end

  after { AnimateIt.reset! }

  it "selects Servo in auto mode only for certified compositions" do
    expect(described_class.backend_for(composition, configured: :auto)).to eq(:servo)

    legacy = Class.new(AnimateIt::Composition)
    expect(described_class.backend_for(legacy, configured: :auto)).to eq(:playwright)
  end

  it "falls back only for operational capture failures and clears partial frames" do
    frames_dir = Pathname(Dir.mktmpdir)
    partial = frames_dir.join("frame-00000.png")
    partial.binwrite("partial")
    primary = instance_double("primary")
    fallback = instance_double("fallback")
    allow(primary).to receive(:capture_frames).and_raise(AnimateIt::CaptureOperationalError, "offline")
    allow(fallback).to receive(:capture_frames).and_return(:complete)
    capturer = described_class::Fallback.new(primary:, fallback:, frames_dir:)

    expect(capturer.capture_frames(frame_list: [0], page_url: "http://example.test")).to eq(:complete)
    expect(partial).not_to exist
  ensure
    FileUtils.remove_entry(frames_dir) if frames_dir&.exist?
  end

  it "does not hide deterministic render failures behind Chromium fallback" do
    primary = instance_double("primary")
    fallback = instance_double("fallback")
    allow(primary).to receive(:capture_frame).and_raise(AnimateIt::CaptureError, "manifest mismatch")
    allow(fallback).to receive(:capture_frame)
    capturer = described_class::Fallback.new(primary:, fallback:)

    expect { capturer.capture_frame(frame: 0, page_url: "http://example.test") }
      .to raise_error(AnimateIt::CaptureError, /manifest mismatch/)
    expect(fallback).not_to have_received(:capture_frame)
  end

  it "reports streamed Servo progress and cancels an active request" do
    frames_dir = Pathname(Dir.mktmpdir)
    previous_endpoint = AnimateIt.config.servo_endpoint
    previous_origins = AnimateIt.config.servo_allowed_origins
    AnimateIt.config.servo_endpoint = "http://127.0.0.1:4178"
    AnimateIt.config.servo_allowed_origins = ["http://example.test"]
    servo = described_class::Servo.new(composition:, host: "http://example.test", frames_dir:)
    allow(servo).to receive(:stream_request) do |_request, &block|
      response = Net::HTTPOK.new("1.1", "200", "OK")
      block.call(response, ['{"status":"progress","captured":1}'])
      block.call(response, ['{"status":"progress","captured":2}'])
    end
    allow(servo).to receive(:cancel)
    checks = 0
    progress = []

    status = servo.capture_frames(
      frame_list: [3, 4],
      page_url: "http://example.test/player",
      on_progress: ->(frame, total) { progress << [frame, total] },
      cancel_check: lambda {
        checks += 1
        checks >= 3
      }
    )

    expect(status).to eq(:cancelled)
    expect(progress).to eq([[4, 2]])
    expect(servo).to have_received(:cancel).with(kind_of(String))
  ensure
    AnimateIt.config.servo_endpoint = previous_endpoint
    AnimateIt.config.servo_allowed_origins = previous_origins
    FileUtils.remove_entry(frames_dir) if frames_dir&.exist?
  end
end
