module AnimateIt
  # Host-app-overridable configuration. Set via the initializer that
  # `bin/rails animate_it:install` generates, or in any initializer:
  #
  #   AnimateIt.configure do |config|
  #     config.mount_path = "/studio"
  #   end
  class Configuration
    attr_accessor :mount_path

    # Host-app stylesheets to load into every rendered frame/filmstrip <head>.
    # Compositions that re-use host partials (which expect the host's component
    # CSS) list the bundles they need here, e.g.:
    #
    #   config.render_stylesheets = %w[application components/star-ratings]
    #
    # Names are passed straight to `stylesheet_link_tag`, so they resolve
    # through the host's asset pipeline. Default empty — a composition built
    # from self-contained markup needs none.
    attr_accessor :render_stylesheets

    def initialize
      @mount_path = "/animate_it"
      @render_stylesheets = []
    end
  end
end
