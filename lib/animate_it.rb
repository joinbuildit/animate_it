require "active_support"
require "active_support/core_ext"

require_relative "animate_it/version"
require_relative "animate_it/errors"
require_relative "animate_it/frame_duration"
require_relative "animate_it/units"
require_relative "animate_it/style"
require_relative "animate_it/easing"
require_relative "animate_it/timing"
require_relative "animate_it/animation_helpers"
require_relative "animate_it/view_helpers"
require_relative "animate_it/frame_context"
require_relative "animate_it/props_schema"
require_relative "animate_it/timeline"
require_relative "animate_it/registry"
require_relative "animate_it/render_store"
require_relative "animate_it/beats"
require_relative "animate_it/chapters"
require_relative "animate_it/animation"
require_relative "animate_it/text_effects"
require_relative "animate_it/scene"
require_relative "animate_it/configuration"
require_relative "animate_it/composition"
require_relative "animate_it/tracks/layer"
require_relative "animate_it/tracks/document"
require_relative "animate_it/tracks/recorder"
require_relative "animate_it/track_document_schema"
require_relative "animate_it/player_manifest"
require_relative "animate_it/embed_styles"
require_relative "animate_it/chapter_navigation"
require_relative "animate_it/embed_runtime"
require_relative "animate_it/runtime"
require_relative "animate_it/embed_helper"
require_relative "animate_it/output"
require_relative "animate_it/frame_capturers"
require_relative "animate_it/video_renderer"
require_relative "animate_it/render_ticket_store"
require_relative "animate_it/image_renderer"
require_relative "animate_it/verification"
require_relative "animate_it/asset_renderer"
require_relative "animate_it/asset_manifest"
# Controllers (app/controllers/animate_it/*) and AnimateIt::RenderJob
# (app/jobs/animate_it/render_job.rb) autoload via Rails — the engine's
# `isolate_namespace AnimateIt` wires `app/` paths into the autoloader.

module AnimateIt
  class << self
    delegate :register, to: :registry

    def config
      @config ||= Configuration.new
    end

    def configure
      yield(config)
    end

    def registry
      @registry ||= Registry.new
    end

    def compositions
      registry.all
    end

    def reset!
      @registry = Registry.new
    end

    # Boot-time + dev-reload entry point. Wired by the engine's
    # `to_prepare` initializer, which fires once at boot and on every
    # autoloader reload after a watched file changes.
    #
    # The host's `app/videos` is in `config.autoload_paths` (set by the
    # engine), so Zeitwerk owns the constants. On reload Zeitwerk has
    # already `remove_const`'d every composition by the time we run, so
    # `eager_load_dir` re-defines them fresh and the `inherited` hook
    # fires — guaranteeing a clean Timeline / @beats / @outputs per
    # reload (no stale segments accumulating across edits).
    def load_compositions!
      return unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

      videos_dir = Rails.root.join("app/videos")
      return unless videos_dir.directory?

      if defined?(Rails.autoloaders) && Rails.autoloaders.main.respond_to?(:eager_load_dir)
        Rails.autoloaders.main.eager_load_dir(videos_dir.to_s)
      else
        # Fallback for environments without Zeitwerk eager_load_dir
        # (older Rails / non-Zeitwerk autoloaders). `load` re-runs the
        # file each time which is fine here because compositions are
        # idempotent re-openable classes.
        videos_dir.glob("**/*.rb").sort.each { |path| load(path.to_s) }
      end

      # After every composition class is loaded, give each one a chance
      # to auto-mount its single nested Scene class (the single-scene
      # shorthand). Idempotent: skips comps that already declared a
      # `scene`/`series`/`audio`.
      compositions.each(&:auto_mount_single_scene!)
    end

    # Dev-reload alias — clears the registry so a renamed or deleted
    # composition id doesn't linger, then re-loads everything.
    def reload_compositions!
      registry.reset!
      load_compositions!
    end
  end
end

require_relative "animate_it/engine" if defined?(Rails::Engine)
