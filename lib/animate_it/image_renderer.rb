require "digest"
require "json"

module AnimateIt
  class ImageRenderer
    attr_reader :composition, :frame, :props, :host

    def initialize(composition:, frame:, props:, host:, cache: true, capture_backend: nil)
      raise Error, "AnimateIt internal rendering is not enabled" unless AnimateIt.config.internal_rendering?

      AnimateIt.load_compositions!
      @composition = resolve_composition(composition)
      @frame = integer_frame(frame)
      @host = host.to_s.delete_suffix("/")
      @cache_enabled = cache == true
      @capture_backend = capture_backend || AnimateIt.config.capture_backend
      validate_composition!
      @props = @composition.props_schema.resolve_for_render(
        props,
        render_origin: @host,
        asset_origins: AnimateIt.config.render_asset_origins
      )
    end

    def render
      cached = Rails.cache.read(cache_key) if @cache_enabled
      return cached if cached

      token = RenderTicketStore.create!(composition:, props:)
      bytes = frame_capturer.capture_frame(frame:, page_url: render_page_url(token))
      Rails.cache.write(cache_key, bytes) if @cache_enabled
      bytes
    ensure
      RenderTicketStore.delete(token) if token
    end

    def etag
      @etag ||= Digest::SHA256.hexdigest(cache_key)
    end

    def cache_key
      @cache_key ||= begin
        payload = {
          animate_it: AnimateIt::VERSION,
          track_schema: TrackDocumentSchema::CURRENT_VERSION,
          player_manifest: PlayerManifest::VERSION,
          runtime: Digest::SHA256.hexdigest(Runtime.source),
          render_cache_version: AnimateIt.config.render_cache_version,
          backend: FrameCapturers.backend_for(composition, configured: @capture_backend),
          backend_version: FrameCapturers.cache_version_for(composition, configured: @capture_backend),
          composition: composition.id,
          width: composition.width,
          height: composition.height,
          frame:,
          props: canonical(props)
        }
        "animate_it/images/#{Digest::SHA256.hexdigest(JSON.generate(payload))}"
      end
    end

    private

    def resolve_composition(value)
      return value if value.is_a?(Class) && value <= Composition

      AnimateIt.registry.fetch(value.to_s)
    end

    def integer_frame(value)
      Integer(value)
    rescue ArgumentError, TypeError
      raise Error, "AnimateIt frame must be an integer"
    end

    def validate_composition!
      raise Error, "AnimateIt image rendering requires a client-driven composition" unless composition.client_driven?
      return if frame.between?(0, composition.duration_in_frames - 1)

      raise Error, "AnimateIt frame #{frame} is outside 0...#{composition.duration_in_frames}"
    end

    def frame_capturer
      @frame_capturer ||= FrameCapturers.build(
        composition:,
        host:,
        backend: @capture_backend
      )
    end

    def render_page_url(token)
      "#{host}#{AnimateIt.config.mount_path}/internal/render_pages/#{token}?pp=disable"
    end

    def canonical(value)
      case value
      when Hash
        value.sort_by { |key, _| key.to_s }.to_h { |key, item| [key.to_s, canonical(item)] }
      when Array
        value.map { |item| canonical(item) }
      else
        value
      end
    end
  end
end
