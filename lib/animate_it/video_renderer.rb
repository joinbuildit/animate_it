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

      return unless audio_segments.any? && AUDIO_INCAPABLE_FORMATS.include?(@output_format)

      raise Error,
            "Composition #{composition.id} declares audio but format=#{@output_format} doesn't support audio. Use :webm/:mp4/:mov."
    end

    class CancelledError < AnimateIt::Error; end

    def render(frame_range: nil, every_nth_frame: 1, props: {}, on_progress: nil, cancel_check: nil)
      FileUtils.mkdir_p(frames_dir)
      FileUtils.mkdir_p(output_path.dirname)

      frame_list = frames(frame_range:, every_nth_frame:)
      capture_status = capture_frames(frame_list, props:, on_progress:, cancel_check:)

      if capture_status == :cancelled || cancel_check&.call
        frame_count = contiguous_frame_count
        encode_video(frame_count:) if frame_count.positive?
        raise CancelledError, "Render cancelled"
      end

      encode_video
      output_path
    end

    private

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

          page.goto(filmstrip_url(props:), waitUntil: "networkidle")
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

    def filmstrip_url(props:)
      query = { pp: "disable" }
      query[:props_json] = JSON.generate(props) if props.present?

      "#{host}#{AnimateIt.config.mount_path}/compositions/#{composition.id}/filmstrip?#{URI.encode_www_form(query)}"
    end

    def encode_video(frame_count: nil)
      return if output_format == :png_sequence # frames already on disk; nothing to encode

      if output_format == :png
        # Single-frame still: copy the captured PNG straight to output_path.
        # frame_range: (n..n) was passed to capture_frames so frame-00000.png
        # is the only one we need.
        FileUtils.cp(frames_dir.join("frame-00000.png"), output_path)
        return
      end

      command = ["ffmpeg", "-y", "-framerate", composition.fps.to_s,
                 "-i", frames_dir.join("frame-%05d.png").to_s]

      audios = audio_segments
      audios.each { |seg| command += ["-i", resolve_audio_path!(seg.source[:path])] }

      command += video_codec_args
      command += ["-frames:v", frame_count.to_s] if frame_count

      if audios.any?
        command += ["-filter_complex", audio_filter_graph(audios), "-map", "0:v", "-map", "[aout]", "-shortest"]
        command += audio_codec_args
      else
        command += ["-an"] # explicit no-audio so output containers like .mov stay clean
      end

      command << output_path.to_s

      run!(command)
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

    # Build an `adelay=...|...,volume=g[aN]` chain per audio input, then mix.
    def audio_filter_graph(audios)
      ms_per_frame = 1000.0 / composition.fps
      legs = audios.each_with_index.map do |seg, i|
        delay_ms = (seg.from_frame * ms_per_frame).round
        gain = seg.source[:gain] || 1.0
        "[#{i + 1}:a]adelay=#{delay_ms}|#{delay_ms},volume=#{gain}[a#{i}]"
      end
      # normalize=0: amix's default rescales every input by 1/N, which
      # silently buries a voice-over under a music bed the moment a second
      # track is declared. Declared gains are the only intended scaling.
      mix = "#{audios.length.times.map { |i| "[a#{i}]" }.join}amix=inputs=#{audios.length}:duration=longest:normalize=0[aout]"
      [legs, mix].flatten.join(";")
    end

    def audio_segments
      composition.timeline.segments.select { |seg| seg.kind == :audio }
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
