require "fileutils"
require "open3"
require "uri"

module AnimateIt
  # Pixel-diff harness comparing the client player with legacy filmstrip.
  class Verification
    Result = Data.define(:frame, :rgb_psnr, :alpha_psnr, :passed) do
      def psnr
        [rgb_psnr, alpha_psnr].min
      end
    end

    attr_reader :composition, :host, :step, :threshold, :alpha_threshold, :output_dir, :props, :ready_timeout

    def initialize(
      composition:,
      host:,
      step: 10,
      threshold: 40.0,
      alpha_threshold: nil,
      output_dir: nil,
      playwright_cli: nil,
      props: {},
      ready_timeout: 30_000
    )
      @composition = composition
      @host = host.delete_suffix("/")
      @step = [step.to_i, 1].max
      @threshold = threshold.to_f
      @alpha_threshold = alpha_threshold.nil? ? @threshold : alpha_threshold.to_f
      @output_dir = Pathname(output_dir || Rails.root.join("tmp/animate_it/verify/#{composition.id}"))
      @playwright_cli = playwright_cli || ENV.fetch("PLAYWRIGHT_CLI_EXECUTABLE_PATH", "npx playwright")
      @props = props.to_h
      @ready_timeout = [ready_timeout.to_i, 1].max
    end

    def call
      require "playwright"
      FileUtils.mkdir_p(output_dir)
      results = []

      Playwright.create(playwright_cli_executable_path: @playwright_cli) do |playwright|
        browser = playwright.chromium.launch(
          headless: true,
          timeout: ready_timeout.to_f,
          args: [
            "--disable-web-security",
            "--disable-lcd-text",
            "--disable-gpu-compositing",
            "--force-color-profile=srgb"
          ]
        )
        begin
          context = browser.new_context(viewport: { width: composition.width, height: composition.height })
          legacy = open_page(context, "filmstrip")
          candidate = open_page(context, "player")

          sample_frames.each do |frame|
            legacy_shot = screenshot(legacy, frame, "legacy")
            candidate_shot = screenshot(candidate, frame, "player")
            results << result_for(frame, legacy_shot, candidate_shot)
          end
        ensure
          browser&.close
        end
      end

      results
    end

    def sample_frames
      max = composition.duration_in_frames - 1
      frames = (0..max).step(step).to_a
      composition.structure_layers.each do |layer|
        [layer.from_frame, layer.to_frame].each do |edge|
          frames.push(edge - 1, edge, edge + 1)
        end
      end
      frames.grep(0..max).sort.uniq
    end

    private

    def open_page(context, endpoint)
      page = context.new_page
      url = page_url(endpoint)
      response = page.goto(url, waitUntil: "networkidle", timeout: ready_timeout)
      unless response&.ok?
        status = response ? "#{response.status} #{response.status_text}" : "no HTTP response"
        raise Error, "Could not open AnimateIt #{endpoint} page at #{url}: #{status}"
      end

      page.wait_for_function(
        'document.documentElement.dataset.animateItReady === "1"',
        timeout: ready_timeout
      )
      page
    rescue Playwright::TimeoutError => e
      raise Error,
            "Timed out after #{ready_timeout}ms waiting for the AnimateIt #{endpoint} page at #{url}. " \
            "Confirm the server is reachable and that the page sets data-animate-it-ready=\"1\". " \
            "(#{e.message})"
    end

    def screenshot(page, frame, label)
      page.evaluate("(n) => window.__animateIt.setFrame(n)", arg: frame)
      if label == "player"
        page.evaluate(<<~JS)
          document.querySelectorAll(".animate-it-layer.is-active").forEach((el) => {
            el.classList.remove("is-active");
            void el.offsetHeight;
            el.classList.add("is-active");
          });
        JS
        page.evaluate("(n) => window.__animateIt.setFrame(n)", arg: frame)
      end
      page.evaluate("() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))")
      path = output_dir.join(format("%<label>s-%<frame>05d.png", label:, frame:))
      page.screenshot(path: path.to_s, omitBackground: true)
      path
    end

    def page_url(endpoint)
      query = { pp: "disable" }
      query[:props_json] = JSON.generate(props) unless props.empty?
      "#{host}#{AnimateIt.config.mount_path}/compositions/#{composition.id}/#{endpoint}?#{URI.encode_www_form(query)}"
    end

    def psnr_between(reference, candidate)
      psnr_between_rgba(decoded_rgba(reference), decoded_rgba(candidate))
    end

    def psnr_between_rgba(reference_rgba, candidate_rgba)
      unless reference_rgba.bytesize == candidate_rgba.bytesize
        raise Error,
              "Cannot compare screenshots with different decoded sizes " \
              "(#{reference_rgba.bytesize} vs #{candidate_rgba.bytesize} RGBA bytes)"
      end

      rgb_error = 0.0
      alpha_error = 0.0
      offset = 0
      while offset < reference_rgba.bytesize
        reference_alpha = reference_rgba.getbyte(offset + 3)
        candidate_alpha = candidate_rgba.getbyte(offset + 3)
        alpha_error += (reference_alpha - candidate_alpha)**2

        3.times do |channel|
          reference_value = reference_rgba.getbyte(offset + channel) * reference_alpha / 255.0
          candidate_value = candidate_rgba.getbyte(offset + channel) * candidate_alpha / 255.0
          rgb_error += (reference_value - candidate_value)**2
        end
        offset += 4
      end

      pixels = reference_rgba.bytesize / 4
      [psnr(rgb_error, pixels * 3), psnr(alpha_error, pixels)]
    end

    def result_for(frame, reference, candidate)
      rgb_psnr, alpha_psnr = psnr_between(reference, candidate)
      result_for_scores(frame, rgb_psnr, alpha_psnr)
    end

    def result_for_scores(frame, rgb_psnr, alpha_psnr)
      passed = rgb_psnr >= threshold && alpha_psnr >= alpha_threshold
      Result.new(frame:, rgb_psnr:, alpha_psnr:, passed:)
    end

    def decoded_rgba(path)
      stdout, stderr, status = Open3.capture3(
        "ffmpeg", "-v", "error", "-i", path.to_s,
        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-"
      )
      raise Error, "ffmpeg could not decode #{path}: #{stderr}" unless status.success?

      stdout
    end

    def psnr(squared_error, samples)
      return Float::INFINITY if squared_error.zero?

      mean_squared_error = squared_error / samples
      10 * Math.log10((255.0**2) / mean_squared_error)
    end
  end
end
