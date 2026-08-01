require "fileutils"
require "json"
require "open3"
require "shellwords"
require "tempfile"
require "uri"
# `playwright` is a development-only gem (deploy image runs `bundle install
# --without development test`). Defer loading until a render is actually
# requested so production boot / asset precompile can load this file
# without the gem present.

module AnimateIt
  class VideoRenderer
    DEFAULT_PLAYWRIGHT_CLI = "npx playwright".freeze

    # Lazy: Rails.root is nil at gem-load time (Bundler.require runs before
    # Rails::Application is fully initialized).
    def self.audio_base
      @audio_base ||= Rails.root.join("app/audio").freeze
    end

    EXTENSION_FOR_FORMAT = {
      mp4: "mp4",
      webm: "webm",
      mov: "mov",
      gif: "gif",
      png_sequence: nil,
      png: "png"
    }.freeze

    AUDIO_INCAPABLE_FORMATS = %i[gif png_sequence png].freeze

    attr_reader :composition, :host, :output_path, :frames_dir, :playwright_cli, :output_format

    def initialize(composition:, host:, output_path:, frames_dir: nil, playwright_cli: nil, format: nil)
      @composition = composition
      @output_format = format || composition.output_format
      @host = host.delete_suffix("/")
      @output_path = Pathname(output_path)
      @frames_dir = Pathname(frames_dir || Rails.root.join("tmp/animate_it/#{composition.id}"))
      @playwright_cli = playwright_cli || ENV.fetch("PLAYWRIGHT_CLI_EXECUTABLE_PATH", DEFAULT_PLAYWRIGHT_CLI)
    end

    class CancelledError < AnimateIt::Error; end

    def render(frame_range: nil, every_nth_frame: 1, props: {}, on_progress: nil, cancel_check: nil,
               reuse_captured_frames: false)
      FileUtils.mkdir_p(frames_dir)
      FileUtils.mkdir_p(output_path.dirname)

      frame_list = frames(frame_range:, every_nth_frame:)
      if reuse_captured_frames
        validate_captured_frames!(frame_list.size)
        capture_status = :complete
      else
        clear_captured_frames!
        capture_status = capture_frames(frame_list, props:, on_progress:, cancel_check:)
      end

      if capture_status == :cancelled || cancel_check&.call
        frame_count = contiguous_frame_count
        encode_video(frame_count:, start_frame: frame_list.first) if frame_count.positive?
        raise CancelledError, "Render cancelled"
      end

      encode_video(frame_count: frame_list.size, start_frame: frame_list.first)
      output_path
    end

    private

    def clear_captured_frames!
      Dir.glob(frames_dir.join("frame-*.png")).each { |path| FileUtils.rm_f(path) }
    end

    def validate_captured_frames!(frame_count)
      missing = frame_count.times.find do |index|
        !frames_dir.join(format("frame-%05d.png", index)).file?
      end
      return unless missing

      raise Error, "Captured frame not found: #{frames_dir.join(format("frame-%05d.png", missing))}"
    end

    def frames(frame_range:, every_nth_frame:)
      range = frame_range || (0...composition.duration_in_frames)
      range.step(every_nth_frame).to_a
    end

    # One Playwright browser, one navigation, N screenshots — all frames are
    # rendered in a single filmstrip page and we just toggle which one is
    # visible between captures via window.__animateIt.setFrame(n).
    def capture_frames(frame_list, props:, on_progress:, cancel_check:)
      require "playwright" # development-only gem; lazy-loaded so deploy image boot doesn't fail
      cancelled = false

      Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
        browser = pw.chromium.launch(headless: true, args: ["--disable-web-security"])
        begin
          context = browser.new_context(
            viewport: { width: composition.width, height: composition.height }
          )
          page = context.new_page

          page.goto(page_url(props:), waitUntil: "networkidle")
          page.wait_for_function('document.documentElement.dataset.animateItReady === "1"')

          frame_list.each_with_index do |frame, index|
            if cancel_check&.call
              cancelled = true
              break
            end

            page.evaluate("(n) => window.__animateIt.setFrame(n)", arg: frame)
            screenshot_path = frames_dir.join(format("frame-%05d.png", index))
            page.screenshot(path: screenshot_path.to_s, omitBackground: true)

            on_progress&.call(frame + 1, frame_list.size)
          end
        ensure
          browser&.close
        end
      end

      cancelled || cancel_check&.call ? :cancelled : :complete
    end

    def page_url(props:)
      query = { pp: "disable" }
      query[:props_json] = JSON.generate(props) if props.present?
      endpoint = composition.client_driven? ? "player" : "filmstrip"

      "#{host}#{AnimateIt.config.mount_path}/compositions/#{composition.id}/#{endpoint}?#{URI.encode_www_form(query)}"
    end

    def encode_video(frame_count: nil, start_frame: 0)
      if output_format == :png_sequence
        publish_png_sequence(frame_count || contiguous_frame_count)
        return
      end

      if output_format == :png
        # Single-frame still: copy the captured PNG straight to output_path.
        # frame_range: (n..n) was passed to capture_frames so frame-00000.png
        # is the only one we need.
        FileUtils.cp(frames_dir.join("frame-00000.png"), output_path)
        return
      end

      command = ["ffmpeg", "-y", "-framerate", composition.fps.to_s,
                 "-i", frames_dir.join("frame-%05d.png").to_s]

      clip_frame_count = frame_count || composition.duration_in_frames
      audios = audio_capable? ? audio_segments(start_frame:, frame_count: clip_frame_count) : []
      audios.each do |segment|
        command += ["-stream_loop", "-1"] if segment.source[:loop]
        command += ["-i", resolve_audio_path!(segment.source[:path])]
      end

      command += video_codec_args
      command += ["-frames:v", frame_count.to_s] if frame_count

      if audios.any?
        command += [
          "-filter_complex",
          audio_filter_graph(audios, start_frame:, frame_count: clip_frame_count),
          "-map", "0:v",
          "-map", "[aout]",
          "-shortest"
        ]
        command += audio_codec_args
      else
        command += ["-an"] # explicit no-audio so output containers like .mov stay clean
      end

      command << output_path.to_s

      run!(command)
    end

    def publish_png_sequence(frame_count)
      FileUtils.mkdir_p(output_path)
      Dir.glob(output_path.join("frame-*.png")).each { |path| FileUtils.rm_f(path) }

      frame_count.times do |index|
        filename = format("frame-%05d.png", index)
        source = frames_dir.join(filename)
        raise Error, "Captured frame not found: #{source}" unless source.file?

        FileUtils.cp(source, output_path.join(filename))
      end
    end

    def video_codec_args
      case output_format
      when :mp4
        ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
      when :webm
        ["-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", "30", "-row-mt", "1"]
      when :mov
        ["-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le"]
      when :gif
        ["-filter_complex",
         "split[s0][s1];[s0]palettegen=reserve_transparent=1[p];[s1][p]paletteuse=alpha_threshold=128"]
      else
        raise Error, "Unsupported format #{output_format.inspect}"
      end
    end

    def audio_codec_args
      case output_format
      when :mp4 then ["-c:a", "aac", "-b:a", "192k"]
      when :webm then ["-c:a", "libopus", "-b:a", "160k"]
      when :mov  then ["-c:a", "pcm_s16le"]
      else            []
      end
    end

    # Trim each source to its timeline window before delaying and mixing it.
    def audio_filter_graph(audios, start_frame: 0, frame_count: composition.duration_in_frames)
      ms_per_frame = 1000.0 / composition.fps
      clip_end_frame = start_frame + frame_count
      legs = audios.each_with_index.map do |segment, index|
        segment_end_frame = segment.duration_frames ? segment.from_frame + segment.duration_frames : composition.duration_in_frames
        overlap_start_frame = [segment.from_frame, start_frame].max
        overlap_end_frame = [segment_end_frame, clip_end_frame].min
        source_start_seconds = (overlap_start_frame - segment.from_frame).fdiv(composition.fps)
        overlap_seconds = (overlap_end_frame - overlap_start_frame).fdiv(composition.fps)
        delay_ms = ((overlap_start_frame - start_frame) * ms_per_frame).round
        gain = segment.source[:gain] || 1.0
        "[#{index + 1}:a]atrim=start=#{source_start_seconds}:duration=#{overlap_seconds}," \
          "asetpts=PTS-STARTPTS," \
          "adelay=#{delay_ms}|#{delay_ms},volume=#{gain}[a#{index}]"
      end
      # normalize=0: amix's default rescales every input by 1/N, which
      # silently buries a voice-over under a music bed the moment a second
      # track is declared. Declared gains are the only intended scaling.
      clip_seconds = frame_count.fdiv(composition.fps)
      mix = "#{audios.length.times.map { |i| "[a#{i}]" }.join}" \
            "amix=inputs=#{audios.length}:duration=longest:normalize=0," \
            "apad=whole_dur=#{clip_seconds},atrim=duration=#{clip_seconds}[aout]"
      [legs, mix].flatten.join(";")
    end

    def audio_segments(start_frame: 0, frame_count: composition.duration_in_frames)
      clip_end_frame = start_frame + frame_count
      composition.timeline.segments.select do |segment|
        next false unless segment.kind == :audio

        segment_end_frame = segment.duration_frames ? segment.from_frame + segment.duration_frames : composition.duration_in_frames
        segment.from_frame < clip_end_frame && segment_end_frame > start_frame
      end
    end

    def audio_capable?
      AUDIO_INCAPABLE_FORMATS.exclude?(output_format)
    end

    def resolve_audio_path!(path)
      candidate = Pathname.new(path).absolute? ? Pathname.new(path) : self.class.audio_base.join(path)
      raise Error, "Audio file not found: #{path}" unless candidate.file?

      candidate.to_s
    end

    def contiguous_frame_count
      count = 0
      loop do
        path = frames_dir.join(format("frame-%05d.png", count))
        break unless path.exist?

        count += 1
      end
      count
    end

    def run!(command)
      stdout, stderr, status = Open3.capture3(*command)
      return if status.success?

      quoted = command.shelljoin
      raise Error, "Command failed: #{quoted}\n#{stdout}\n#{stderr}"
    end
  end
end
