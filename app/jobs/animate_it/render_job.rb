module AnimateIt
  class RenderJob < ApplicationJob
    queue_as :default

    # `_options` remains as a compatibility slot for render jobs serialized by
    # releases that exposed concurrency settings but never applied them.
    def perform(render_id, composition_id, host, output_path, frames_dir, props = {}, _options = {})
      AnimateIt.load_compositions!
      composition = AnimateIt.registry.fetch(composition_id)

      RenderStore.start!(render_id)
      VideoRenderer.new(
        composition:,
        host:,
        output_path:,
        frames_dir:
      ).render(
        props:,
        cancel_check: -> { RenderStore.cancelled?(render_id) },
        on_progress: ->(frame, total_frames) { RenderStore.progress!(render_id, frame:, total_frames:) }
      )
      RenderStore.complete!(render_id)
    rescue VideoRenderer::CancelledError
      RenderStore.cancel!(render_id)
    rescue StandardError => e
      RenderStore.fail!(render_id, e)
      raise
    end
  end
end
