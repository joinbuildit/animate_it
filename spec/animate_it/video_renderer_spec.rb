require "rails_helper"

RSpec.describe AnimateIt::VideoRenderer do
  let(:composition) do
    Class.new(AnimateIt::Composition) do
      fps 20
      duration 5.seconds

      audio "voice.mp3", from: 1.second, duration: 2.seconds, gain: 0.8
      audio_loop "music.mp3", from: 0.5.seconds, duration: 3.seconds, gain: 0.2
    end
  end
  let(:partial_composition) do
    Class.new(AnimateIt::Composition) do
      fps 30
      duration 6.seconds

      audio "before.mp3", from: 0, duration: 20.frames
      audio_loop "music.mp3", duration: 180.frames
      audio "voice.mp3", from: 60.frames, duration: 90.frames
      audio "effect.mp3", from: 100.frames, duration: 15.frames
    end
  end
  let(:tmp_dir) { Pathname(Dir.mktmpdir) }

  after { FileUtils.remove_entry(tmp_dir) }

  def renderer(format, for_composition: composition)
    described_class.new(
      composition: for_composition,
      host: "http://example.test",
      output_path: tmp_dir.join("output.#{format}"),
      frames_dir: tmp_dir.join("frames"),
      format: format
    )
  end

  def encoded_command(for_composition, frame_count:, start_frame:)
    video_renderer = renderer(:mp4, for_composition: for_composition)
    command = nil
    allow(video_renderer).to receive(:resolve_audio_path!) { |path| "/audio/#{path}" }
    allow(video_renderer).to receive(:run!) { |args| command = args }
    video_renderer.send(:encode_video, frame_count: frame_count, start_frame: start_frame)
    command
  end

  it "trims audio segments and pads the mix to composition duration" do
    filter_graph = renderer(:mp4).send(:audio_filter_graph, composition.timeline.segments)

    expect(filter_graph).to include("[1:a]atrim=start=0.0:duration=2.0")
    expect(filter_graph).to include("[2:a]atrim=start=0.0:duration=3.0")
    expect(filter_graph).to include("apad=whole_dur=5.0,atrim=duration=5.0[aout]")
  end

  it "loops only audio_loop inputs" do
    video_renderer = renderer(:mp4)
    command = nil
    allow(video_renderer).to receive(:resolve_audio_path!) { |path| "/audio/#{path}" }
    allow(video_renderer).to receive(:run!) { |args| command = args }

    video_renderer.send(:encode_video)

    input_options = command.each_cons(4).to_a
    expect(input_options).to include(["-stream_loop", "-1", "-i", "/audio/music.mp3"])
    expect(input_options).not_to include(["-stream_loop", "-1", "-i", "/audio/voice.mp3"])
  end

  it "renders audio compositions silently in audio-incapable formats" do
    gif_renderer = renderer(:gif)
    command = nil
    allow(gif_renderer).to receive(:resolve_audio_path!)
    allow(gif_renderer).to receive(:run!) { |args| command = args }

    gif_renderer.send(:encode_video)

    expect(gif_renderer).not_to have_received(:resolve_audio_path!)
    expect(command).to include("-an")

    sequence_renderer = renderer(:png_sequence)
    FileUtils.mkdir_p(sequence_renderer.frames_dir)
    FileUtils.touch(sequence_renderer.frames_dir.join("frame-00000.png"))
    sequence_renderer.send(:encode_video, frame_count: 1)
    expect(sequence_renderer.output_path.join("frame-00000.png")).to exist

    png_renderer = renderer(:png)
    FileUtils.mkdir_p(png_renderer.frames_dir)
    FileUtils.touch(png_renderer.frames_dir.join("frame-00000.png"))
    expect { png_renderer.send(:encode_video) }.not_to raise_error
  end

  it "keeps audio streams for video containers" do
    { mp4: "aac", webm: "libopus", mov: "pcm_s16le" }.each do |format, codec|
      video_renderer = renderer(format)
      command = nil
      allow(video_renderer).to receive(:resolve_audio_path!).and_return("/audio/source.mp3")
      allow(video_renderer).to receive(:run!) { |args| command = args }

      video_renderer.send(:encode_video)

      expect(command).to include("-map", "[aout]")
      expect(command).to include("-c:a", codec)
    end
  end

  it "keeps gain within the browser audio volume range" do
    expect { Class.new(AnimateIt::Composition) { audio "too-loud.mp3", gain: 1.1 } }
      .to raise_error(ArgumentError, /between 0.0 and 1.0/)
    expect { Class.new(AnimateIt::Composition) { audio "invalid.mp3", gain: "loud" } }
      .to raise_error(ArgumentError, /must be a number/)
  end

  it "selects, rebases, and trims audio overlapping a partial range" do
    command = encoded_command(partial_composition, frame_count: 91, start_frame: 30)
    filter_graph = command.fetch(command.index("-filter_complex") + 1)
    input_options = command.each_cons(4).to_a

    expect(command).not_to include("/audio/before.mp3")
    expect(command).to include("-frames:v", "91")
    expect(input_options).to include(["-stream_loop", "-1", "-i", "/audio/music.mp3"])
    expect(filter_graph).to include("atrim=start=1.0:duration=#{91.fdiv(30)}")
    expect(filter_graph).to include("atrim=start=0.0:duration=#{61.fdiv(30)}")
    expect(filter_graph).to include("atrim=start=0.0:duration=0.5")
    expect(filter_graph).to include("adelay=1000|1000")
    expect(filter_graph).to include("adelay=2333|2333")
    expect(filter_graph).to include("apad=whole_dur=#{91.fdiv(30)}")
  end

  it "encodes a selected frame range from its first frame" do
    video_renderer = renderer(:mp4)
    allow(video_renderer).to receive(:capture_frames).and_return(:complete)
    allow(video_renderer).to receive(:encode_video)

    video_renderer.render(frame_range: 30..120)

    expect(video_renderer).to have_received(:encode_video).with(frame_count: 91, start_frame: 30)
  end

  it "reuses a complete ordered capture without opening the browser again" do
    video_renderer = renderer(:mp4)
    FileUtils.mkdir_p(video_renderer.frames_dir)
    2.times { |index| FileUtils.touch(video_renderer.frames_dir.join(format("frame-%05d.png", index))) }
    allow(video_renderer).to receive(:capture_frames)
    allow(video_renderer).to receive(:encode_video)

    video_renderer.render(frame_range: 30..31, reuse_captured_frames: true)

    expect(video_renderer).not_to have_received(:capture_frames)
    expect(video_renderer).to have_received(:encode_video).with(frame_count: 2, start_frame: 30)
  end

  it "rejects an incomplete shared capture before encoding" do
    video_renderer = renderer(:mp4)
    FileUtils.mkdir_p(video_renderer.frames_dir)
    FileUtils.touch(video_renderer.frames_dir.join("frame-00000.png"))
    allow(video_renderer).to receive(:capture_frames)
    allow(video_renderer).to receive(:encode_video)

    expect { video_renderer.render(frame_range: 30..31, reuse_captured_frames: true) }
      .to raise_error(AnimateIt::Error, /frame-00001\.png/)
    expect(video_renderer).not_to have_received(:capture_frames)
    expect(video_renderer).not_to have_received(:encode_video)
  end

  it "encodes captured cancellation frames from the selected range start" do
    video_renderer = renderer(:mp4)
    FileUtils.mkdir_p(video_renderer.frames_dir)
    10.times { |index| FileUtils.touch(video_renderer.frames_dir.join(format("frame-%05d.png", index))) }
    allow(video_renderer).to receive(:capture_frames) do
      3.times { |index| FileUtils.touch(video_renderer.frames_dir.join(format("frame-%05d.png", index))) }
      :cancelled
    end
    allow(video_renderer).to receive(:encode_video)

    expect { video_renderer.render(frame_range: 30..120) }
      .to raise_error(described_class::CancelledError)
    expect(video_renderer).to have_received(:encode_video).with(frame_count: 3, start_frame: 30)
  end
end
