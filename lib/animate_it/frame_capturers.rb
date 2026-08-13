require "json"
require "fileutils"
require "net/http"
require "pathname"
require "securerandom"
require "uri"

module AnimateIt
  module FrameCapturers
    module_function

    def backend_for(composition, configured: AnimateIt.config.capture_backend)
      backend = configured.to_sym
      return :servo if backend == :servo
      return :servo if backend == :auto && composition.servo_compatible?

      :playwright
    end

    def build(composition:, host:, frames_dir: nil, playwright_cli: nil, backend: AnimateIt.config.capture_backend)
      playwright = lambda do
        Playwright.new(composition:, host:, frames_dir:, playwright_cli:)
      end

      case backend.to_sym
      when :playwright
        playwright.call
      when :servo
        Servo.new(composition:, host:, frames_dir:)
      when :auto
        return playwright.call unless composition.servo_compatible?

        Fallback.new(
          primary: Servo.new(composition:, host:, frames_dir:),
          fallback: playwright.call,
          frames_dir:
        )
      else
        raise ArgumentError, "Unknown capture backend: #{backend.inspect}"
      end
    end

    # Cache identity must never perform I/O: it is evaluated before Rails can
    # answer If-None-Match. Hosts can pin ANIMATE_IT_SERVO_VERSION to the
    # worker revision they deploy.
    def cache_version_for(composition, configured: AnimateIt.config.capture_backend)
      if configured.to_sym == :auto && composition.servo_compatible?
        playwright = Gem.loaded_specs["playwright-ruby-client"]&.version || "unknown"
        return "auto:servo:#{AnimateIt.config.servo_version}:playwright:#{playwright}"
      end

      case backend_for(composition, configured:)
      when :servo then "servo:#{AnimateIt.config.servo_version}"
      when :playwright then "playwright:#{Gem.loaded_specs["playwright-ruby-client"]&.version || "unknown"}"
      end
    end

    class Playwright
      DEFAULT_CLI = "npx playwright".freeze

      def initialize(composition:, host:, frames_dir: nil, playwright_cli: nil)
        @composition = composition
        @host = host
        @frames_dir = Pathname(frames_dir) if frames_dir
        @playwright_cli = playwright_cli || ENV.fetch("PLAYWRIGHT_CLI_EXECUTABLE_PATH", DEFAULT_CLI)
      end

      def capture_frames(frame_list:, page_url:, on_progress: nil, cancel_check: nil)
        cancelled = false
        with_page(page_url) do |page|
          frame_list.each_with_index do |frame, index|
            if cancel_check&.call
              cancelled = true
              break
            end

            seek(page, frame)
            page.screenshot(path: frame_path(index).to_s, omitBackground: true)
            on_progress&.call(frame + 1, frame_list.size)
          end
        end

        cancelled || cancel_check&.call ? :cancelled : :complete
      end

      def capture_frame(frame:, page_url:)
        with_page(page_url) do |page|
          seek(page, frame)
          return page.screenshot(omitBackground: true)
        end
      end

      def version
        "playwright"
      end

      private

      def with_page(page_url)
        require "playwright"

        ::Playwright.create(playwright_cli_executable_path: @playwright_cli) do |playwright|
          browser = playwright.chromium.launch(headless: true, args: ["--disable-web-security"])
          begin
            context = browser.new_context(viewport: { width: @composition.width, height: @composition.height })
            page = context.new_page
            response = page.goto(page_url, waitUntil: "networkidle")
            unless response&.ok?
              status = response ? "#{response.status} #{response.status_text}" : "no HTTP response"
              raise CaptureOperationalError, "Could not open AnimateIt page at #{page_url}: #{status}"
            end

            wait_for_readiness!(page)
            validate_manifest!(page) if @composition.client_driven?
            yield(page)
          ensure
            browser&.close
          end
        end
      rescue CaptureError
        raise
      rescue StandardError => e
        raise CaptureOperationalError, "Playwright capture failed: #{e.message}"
      end

      def wait_for_readiness!(page)
        page.wait_for_function(<<~JS.squish)
          document.documentElement.dataset.animateItReady === "1" ||
            document.documentElement.dataset.animateItError
        JS
        message = page.evaluate("() => document.documentElement.dataset.animateItError || null")
        raise CaptureError, "AnimateIt player failed readiness: #{message}" if message.present?
      end

      def validate_manifest!(page)
        manifest = page.evaluate(<<~JS.squish)
          () => {
            const node = document.querySelector("script[data-animate-it-manifest]");
            return node ? JSON.parse(node.textContent) : null;
          }
        JS
        expected = @composition.player_manifest.as_json
        unless manifest.is_a?(Hash) &&
               manifest.values_at("version", "id", "width", "height", "duration") ==
               expected.values_at("version", "id", "width", "height", "duration")
          raise CaptureError, "AnimateIt player manifest does not match #{@composition.id.inspect}"
        end
      end

      def seek(page, frame)
        page.evaluate("(n) => window.__animateIt.setFrame(n)", arg: frame)
      end

      def frame_path(index)
        raise CaptureError, "A frames directory is required for batch capture" unless @frames_dir

        @frames_dir.join(format("frame-%05d.png", index))
      end
    end

    class Servo
      def initialize(composition:, host:, frames_dir: nil)
        @composition = composition
        @host = host
        @frames_dir = Pathname(frames_dir) if frames_dir
        endpoint = AnimateIt.config.servo_endpoint
        raise CaptureOperationalError, "AnimateIt Servo endpoint is not configured" if endpoint.blank?

        @endpoint = URI(endpoint.delete_suffix("/"))
      end

      def capture_frames(frame_list:, page_url:, on_progress: nil, cancel_check: nil)
        raise CaptureError, "A frames directory is required for batch capture" unless @frames_dir

        request_id = SecureRandom.uuid
        return :cancelled if cancel_check&.call

        validate_page_url!(page_url)

        stream_batch(
          payload(request_id, page_url, frame_list).merge(output_dir: @frames_dir.to_s),
          frame_list,
          request_id,
          on_progress:,
          cancel_check:
        )
      end

      def capture_frame(frame:, page_url:)
        validate_page_url!(page_url)
        request_id = SecureRandom.uuid
        response = post_json("/v1/captures/frame", payload(request_id, page_url, [frame]))
        raise_response!(response) unless response.is_a?(Net::HTTPSuccess) && response["Content-Type"].to_s.start_with?("image/png")

        response.body
      end

      def version
        response = request(Net::HTTP::Get.new(endpoint_uri("/v1/health")))
        return "servo-unavailable" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        data["servo_version"] || data["servo_revision"] || "servo"
      rescue StandardError
        "servo-unavailable"
      end

      private

      def payload(request_id, page_url, frames)
        {
          request_id:,
          url: page_url,
          composition: @composition.id,
          width: @composition.width,
          height: @composition.height,
          duration: @composition.duration_in_frames,
          manifest_version: PlayerManifest::VERSION,
          frames:,
          transparency: true,
          ready_timeout_ms: AnimateIt.config.servo_ready_timeout
        }
      end

      def stream_batch(payload, frame_list, request_id, on_progress:, cancel_check:)
        request = json_request(Net::HTTP::Post, "/v1/captures/frames", payload)
        progress_count = 0
        monitor_finished = false
        cancel_monitor = start_cancel_monitor(request_id, cancel_check) { monitor_finished }
        result = catch(:animate_it_cancelled) do
          stream_request(request) do |response, chunks|
            raise_response!(response) unless response.is_a?(Net::HTTPSuccess)

            chunks.each do |line|
              if cancel_check&.call
                cancel(request_id)
                throw :animate_it_cancelled, :cancelled
              end

              event = JSON.parse(line)
              event_status = event["status"] || event["type"]
              throw :animate_it_cancelled, :cancelled if event_status == "cancelled"
              raise_event_error!(event) if event_status == "error"

              next_count = event["captured"] || event["completed"]
              next_count ||= event["index"].to_i + 1 if event.key?("index")
              next_count ||= progress_count + 1 if %w[frame progress captured].include?(event_status)
              next unless next_count && next_count.to_i > progress_count

              progress_count = [next_count.to_i, frame_list.size].min
              frame = frame_list.fetch(progress_count - 1)
              on_progress&.call(frame + 1, frame_list.size)
            end
          end
          :complete
        end
        return result if result == :cancelled

        validate_batch_frames!(frame_list)
        while progress_count < frame_list.size
          progress_count += 1
          on_progress&.call(frame_list.fetch(progress_count - 1) + 1, frame_list.size)
        end
        :complete
      rescue JSON::ParserError => e
        raise CaptureOperationalError, "Servo returned an invalid batch response: #{e.message}"
      ensure
        monitor_finished = true
        cancel_monitor&.join(0.1)
      end

      def start_cancel_monitor(request_id, cancel_check, &finished)
        return unless cancel_check

        Thread.new do
          Thread.current.report_on_exception = false
          until finished.call
            if cancel_check.call
              cancel(request_id)
              break
            end
            sleep(0.05)
          end
        end
      end

      def stream_request(request)
        buffer = +""
        response = nil
        Net::HTTP.start(
          @endpoint.host,
          @endpoint.port,
          use_ssl: @endpoint.scheme == "https",
          open_timeout: 2,
          read_timeout: (AnimateIt.config.servo_ready_timeout / 1000.0) + 30
        ) do |http|
          http.request(request) do |streamed_response|
            response = streamed_response
            unless response.is_a?(Net::HTTPSuccess)
              streamed_response.read_body { |chunk| buffer << chunk }
              response.instance_variable_set(:@body, buffer)
              yield(response, [])
              next
            end

            streamed_response.read_body do |chunk|
              buffer << chunk
              lines = buffer.split("\n", -1)
              buffer = lines.pop
              yield(response, lines.compact_blank) if lines.any?
            end
          end
        end
        yield(response, [buffer]) if buffer.present?
      rescue IOError, SystemCallError, Timeout::Error, SocketError => e
        raise CaptureOperationalError, "Servo worker is unavailable: #{e.message}"
      end

      def validate_batch_frames!(frame_list)
        missing = frame_list.each_index.find do |index|
          !@frames_dir.join(format("frame-%05d.png", index)).file?
        end
        raise CaptureOperationalError, "Servo did not write captured frame #{missing}" if missing
      end

      def cancel(request_id)
        request(Net::HTTP::Delete.new(endpoint_uri("/v1/captures/#{request_id}")))
      rescue StandardError
        nil
      end

      def post_json(path, payload)
        request(json_request(Net::HTTP::Post, path, payload))
      end

      def json_request(request_class, path, payload)
        request = request_class.new(endpoint_uri(path))
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        request
      end

      def request(request)
        Net::HTTP.start(
          @endpoint.host,
          @endpoint.port,
          use_ssl: @endpoint.scheme == "https",
          open_timeout: 2,
          read_timeout: (AnimateIt.config.servo_ready_timeout / 1000.0) + 30
        ) { |http| http.request(request) }
      rescue IOError, SystemCallError, Timeout::Error, SocketError => e
        raise CaptureOperationalError, "Servo worker is unavailable: #{e.message}"
      end

      def endpoint_uri(path)
        URI.join("#{@endpoint}/", path.delete_prefix("/"))
      end

      def raise_response!(response)
        payload = JSON.parse(response.body)
        code, message = error_details(payload["error"], payload["message"] || response.message)
        error_class = response.code.to_i.in?([400, 422]) ? CaptureError : CaptureOperationalError
        raise error_class, "Servo capture failed (#{response.code}, #{code}): #{message}"
      rescue JSON::ParserError
        raise CaptureOperationalError, "Servo capture failed (#{response.code}): #{response.body}"
      end

      def raise_event_error!(event)
        code, message = error_details(event["error"], event["message"])
        error_class = code.in?(%w[invalid_capture_request invalid_player]) ? CaptureError : CaptureOperationalError
        raise error_class, "Servo capture failed (#{code}): #{message}"
      end

      def error_details(error, fallback)
        if error.is_a?(Hash)
          [error["code"] || "render_failed", error["message"] || fallback || "unknown error"]
        else
          ["render_failed", error.presence || fallback || "unknown error"]
        end
      end

      def validate_page_url!(page_url)
        origin = normalized_origin(page_url)
        allowed = AnimateIt.config.servo_allowed_origins.filter_map { |value| normalized_origin(value) }
        return if origin && allowed.include?(origin)

        raise CaptureError, "Servo page URL must use a configured allowed origin"
      end

      def normalized_origin(value)
        uri = URI(value.to_s)
        return unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil?

        default_port = uri.scheme == "https" ? 443 : 80
        port = uri.port == default_port ? nil : ":#{uri.port}"
        "#{uri.scheme}://#{uri.host.downcase}#{port}"
      rescue URI::InvalidURIError
        nil
      end
    end

    class Fallback
      def initialize(primary:, fallback:, frames_dir: nil)
        @primary = primary
        @fallback = fallback
        @frames_dir = Pathname(frames_dir) if frames_dir
      end

      def capture_frames(**arguments)
        @primary.capture_frames(**arguments)
      rescue CaptureOperationalError
        clear_partial_frames
        @fallback.capture_frames(**arguments)
      end

      def capture_frame(**arguments)
        @primary.capture_frame(**arguments)
      rescue CaptureOperationalError
        @fallback.capture_frame(**arguments)
      end

      def version
        "auto:#{@primary.version}:#{@fallback.version}"
      end

      private

      def clear_partial_frames
        return unless @frames_dir

        Dir.glob(@frames_dir.join("frame-*.png")).each { |path| FileUtils.rm_f(path) }
      end
    end
  end
end
