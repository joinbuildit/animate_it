require "rails/engine"

module AnimateIt
  class Engine < ::Rails::Engine
    isolate_namespace AnimateIt

    # `app/videos/` is automatically autoloaded + reloaded by Rails: the
    # host's `paths.add "app", glob: "*"` default registers every
    # `app/<subdir>/` with Zeitwerk's `main` autoloader, which has reload
    # enabled in development. We don't need to add the path manually.
    #
    # On boot AND on every dev-mode reload (after Zeitwerk has cleared
    # old constants and removed orphaned descendants), reset the registry
    # and eager-load `app/videos` so composition classes self-register
    # via the `id "..."` DSL before any request hits `AnimateIt.compositions`,
    # the Studio UI, or the renderer.
    #
    # Reload sequence in development:
    #   1. file changes under app/videos/
    #   2. Rails reloader → Zeitwerk reload → `remove_const` for every
    #      autoloaded composition class
    #   3. our `to_prepare` callback → `AnimateIt.reload_compositions!`
    #      → registry.reset! + eager_load_dir → every class redefines
    #      from scratch, `inherited` fires, fresh Timeline/@beats/@outputs.
    initializer "animate_it.load_compositions" do
      Rails.application.config.to_prepare do
        AnimateIt.reload_compositions!
      end
    end

    initializer "animate_it.embed_helper" do
      ActiveSupport.on_load(:action_view) do
        include AnimateIt::EmbedHelper
        include AnimateIt::ChapterNavigationHelper
      end
    end

    initializer "animate_it.action_controller_renderer" do
      ActiveSupport.on_load(:action_controller) do
        ActionController::Renderers.add :animate_it do |options, _|
          renderer = AnimateIt::ImageRenderer.new(
            composition: options.fetch(:composition),
            frame: options.fetch(:frame, 0),
            props: options.fetch(:props, {}),
            host: request.base_url,
            cache: options.fetch(:cache, true)
          )

          response.etag = renderer.etag
          if request.fresh?(response)
            self.status = :not_modified
            self.content_type = "image/png"
            ""
          else
            self.content_type = "image/png"
            response.headers["Content-Disposition"] = "inline"
            renderer.render
          end
        end
      end
    end
  end
end
