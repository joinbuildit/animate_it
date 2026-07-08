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
  end
end
