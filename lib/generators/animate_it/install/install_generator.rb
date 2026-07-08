require "rails/generators/base"

module AnimateIt
  module Generators
    # Installs AnimateIt into the host app:
    #   bin/rails generate animate_it:install
    #
    # 1. Copies an opinionated initializer that owns engine config.
    # 2. Inserts a `mount AnimateIt::Engine` line into config/routes.rb,
    #    placed AFTER `devise_for` if Devise is in use (so warden serializers
    #    register correctly — see config/routes.rb in the host app).
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install AnimateIt: copy initializer and mount the engine in routes"

      def copy_initializer
        template "animate_it.rb", "config/routes.rb".sub("routes.rb", "initializers/animate_it.rb")
      end

      def add_route
        routes_path = Rails.root.join("config/routes.rb")
        contents = File.exist?(routes_path) ? File.read(routes_path) : ""

        return say_status(:exists, "AnimateIt::Engine already mounted in config/routes.rb") if contents.include?("AnimateIt::Engine")

        snippet = <<~ROUTE.chomp
          \n  # AnimateIt engine — mount AFTER devise_for so warden serializers register correctly.
            mount AnimateIt::Engine, at: AnimateIt.config.mount_path if Rails.env.local?
        ROUTE

        if contents.include?("devise_for")
          inject_into_file "config/routes.rb", snippet, after: /devise_for[^\n]*\n/
        else
          route "mount AnimateIt::Engine, at: AnimateIt.config.mount_path if Rails.env.local?"
        end
      end
    end
  end
end
