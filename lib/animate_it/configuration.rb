module AnimateIt
  # Host-app-overridable configuration. Set via the initializer that
  # `bin/rails animate_it:install` generates, or in any initializer:
  #
  #   AnimateIt.configure do |config|
  #     config.mount_path = "/studio"
  #   end
  class Configuration
    CAPTURE_BACKENDS = %i[playwright servo auto].freeze

    attr_accessor :mount_path, :render_stylesheets, :servo_endpoint,
                  :servo_allowed_origins, :render_asset_origins,
                  :render_cache_version, :internal_rendering,
                  :render_ticket_ttl, :render_props_max_bytes,
                  :render_prop_string_max_bytes, :servo_ready_timeout,
                  :servo_version

    attr_reader :capture_backend

    # Host-app stylesheets to load into every rendered frame/filmstrip <head>.
    # Compositions that re-use host partials (which expect the host's component
    # CSS) list the bundles they need here, e.g.:
    #
    #   config.render_stylesheets = %w[application components/star-ratings]
    #
    # Names are passed straight to `stylesheet_link_tag`, so they resolve
    # through the host's asset pipeline. Default empty — a composition built
    # from self-contained markup needs none.
    def initialize
      @mount_path = "/animate_it"
      @render_stylesheets = []
      @capture_backend = :playwright
      @servo_endpoint = nil
      @servo_allowed_origins = []
      @render_asset_origins = []
      @render_cache_version = "development"
      @internal_rendering = false
      @render_ticket_ttl = 60
      @render_props_max_bytes = 65_536
      @render_prop_string_max_bytes = 16_384
      @servo_ready_timeout = 30_000
      @servo_version = ENV.fetch("ANIMATE_IT_SERVO_VERSION", "unknown")
    end

    def capture_backend=(value)
      backend = value.to_sym
      raise ArgumentError, "capture_backend must be one of: #{CAPTURE_BACKENDS.join(", ")}" unless CAPTURE_BACKENDS.include?(backend)

      @capture_backend = backend
    end

    def internal_rendering?
      internal_rendering == true
    end
  end
end
