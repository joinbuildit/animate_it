require "rails_helper"

RSpec.describe AnimateIt::VideoRenderer, :aggregate_failures do
  let(:tmp_dir) { Pathname(Dir.mktmpdir("animate-it-ffmpeg")) }
  let(:frames_dir) { tmp_dir.join("frames") }

  before do
    skip "ffmpeg and ffprobe are required" unless system("ffmpeg -version >/dev/null 2>&1") && system("ffprobe -version >/dev/null 2>&1")

    FileUtils.mkdir_p(frames_dir)
    seed_frame = frames_dir.join("seed.png")
    _stdout, stderr, status = Open3.capture3(
      "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=#285ab4:s=16x16",
      "-frames:v", "1", "-update", "1", seed_frame.to_s
    )
    raise "could not create fixture frame: #{stderr}" unless status.success?

    30.times do |index|
      FileUtils.cp(seed_frame, frames_dir.join(format("frame-%05d.png", index)))
    end
    FileUtils.rm_f(seed_frame)
  end

  after { FileUtils.remove_entry(tmp_dir) if tmp_dir.exist? }

  it "encodes declared trim and loop windows into a duration-aligned MP4" do
    tone = write_wav("tone.wav", duration: 2.0) { |time| Math.sin(2 * Math::PI * 440 * time) * 0.35 }
    loop_tone = write_wav("loop.wav", duration: 0.2) { |time| Math.sin(2 * Math::PI * 880 * time) * 0.25 }
    composition = build_composition(duration: 2.seconds) do
      audio tone.to_s, from: 0.5.seconds, duration: 0.5.seconds
      audio_loop loop_tone.to_s, from: 1.second, duration: 1.second
    end
    output = tmp_dir.join("trim-loop.mp4")

    encode(composition, output, frame_count: 20)

    probe = ffprobe(output)
    expect(probe.dig("format", "duration").to_f).to be_within(0.08).of(2.0)
    expect(probe.fetch("streams").map { |stream| stream.fetch("codec_type") }).to contain_exactly("video", "audio")
    expect(rms_at(output, start: 0.7, duration: 0.1)).to be > 500
    expect(rms_at(output, start: 1.7, duration: 0.1)).to be > 300
  end

  it "trims audio and seeks into its source for partial renders" do
    tone = write_wav("trim-source.wav", duration: 2.0) { |time| Math.sin(2 * Math::PI * 440 * time) * 0.4 }
    composition = build_composition(duration: 2.seconds) do
      audio tone.to_s, from: 0.5.seconds, duration: 0.5.seconds
    end
    output = tmp_dir.join("trimmed.mp4")
    encode(composition, output, frame_count: 20)

    expect(rms_at(output, start: 0.7, duration: 0.1)).to be > 500
    expect(rms_at(output, start: 1.3, duration: 0.1)).to be < 100

    offset_source = write_wav("offset-source.wav", duration: 3.0) do |time|
      time < 1.0 ? 0.0 : Math.sin(2 * Math::PI * 660 * time) * 0.4
    end
    partial = build_composition(duration: 3.seconds) { audio offset_source.to_s, duration: 3.seconds }
    partial_output = tmp_dir.join("partial.mp4")
    encode(partial, partial_output, frame_count: 10, start_frame: 10)

    expect(ffprobe(partial_output).dig("format", "duration").to_f).to be_within(0.08).of(1.0)
    expect(rms_at(partial_output, start: 0.2, duration: 0.1)).to be > 500
  end

  it "publishes silent GIF and PNG sequence outputs" do
    tone = write_wav("silent-source.wav", duration: 1.0) { |time| Math.sin(2 * Math::PI * 440 * time) * 0.3 }
    composition = build_composition(duration: 0.5.seconds) { audio tone.to_s, duration: 0.5.seconds }

    gif_output = tmp_dir.join("silent.gif")
    encode(composition, gif_output, frame_count: 5, format: :gif)
    expect(gif_output).to be_file
    expect(ffprobe(gif_output).fetch("streams").map { |stream| stream.fetch("codec_type") }).to eq(["video"])

    sequence_output = tmp_dir.join("png-sequence")
    encode(composition, sequence_output, frame_count: 5, format: :png_sequence)
    frames = sequence_output.glob("frame-*.png").sort
    expect(frames.size).to eq(5)
    expect(frames).to all(satisfy { |path| path.binread(8) == "\x89PNG\r\n\x1A\n".b })
  end

  private

  def build_composition(duration:, &block)
    Class.new(AnimateIt::Composition) do
      fps 10
      size 16, 16
      duration duration
      class_eval(&block)
    end
  end

  def encode(composition, output, frame_count:, start_frame: 0, format: :mp4)
    described_class.new(
      composition: composition,
      host: "http://example.test",
      output_path: output,
      frames_dir: frames_dir,
      format: format
    ).send(:encode_video, frame_count: frame_count, start_frame: start_frame)
  end

  def ffprobe(path)
    stdout, stderr, status = Open3.capture3(
      "ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type", "-of", "json", path.to_s
    )
    raise "ffprobe failed: #{stderr}" unless status.success?

    JSON.parse(stdout)
  end

  def rms_at(path, start:, duration:)
    stdout, stderr, status = Open3.capture3(
      "ffmpeg", "-v", "error", "-i", path.to_s,
      "-af", "atrim=start=#{start}:duration=#{duration},asetpts=PTS-STARTPTS",
      "-ac", "1", "-ar", "8000", "-f", "s16le", "-"
    )
    raise "ffmpeg audio decode failed: #{stderr}" unless status.success?

    samples = stdout.unpack("s<*")
    return 0.0 if samples.empty?

    Math.sqrt(samples.sum { |sample| sample**2 }.fdiv(samples.size))
  end

  def write_wav(filename, duration:, sample_rate: 8_000)
    samples = (sample_rate * duration).to_i.times.map do |index|
      (yield(index.fdiv(sample_rate)).clamp(-1.0, 1.0) * 32_767).round
    end
    data = samples.pack("s<*")
    header = [
      "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, sample_rate,
      sample_rate * 2, 2, 16, "data", data.bytesize
    ].pack("A4VA4A4VvvVVvvA4V")
    path = tmp_dir.join(filename)
    File.binwrite(path, header + data)
    path
  end
end
