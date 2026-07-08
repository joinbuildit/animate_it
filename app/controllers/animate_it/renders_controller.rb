module AnimateIt
  class RendersController < ApplicationController
    def show
      @render_id = params[:id]
      # `params[:id]` here is a render UUID, not a composition id — look up
      # the render record first to learn which composition produced it.
      render_record = RenderStore.find(@render_id)
      return head(:not_found) unless render_record

      AnimateIt.load_compositions!
      @composition = AnimateIt.registry.fetch(render_record.composition_id)
      @output_path = Pathname(render_record.output_path)
      if params[:download].present? && @output_path.exist?
        send_file @output_path, type: Mime::Type.lookup_by_extension(@output_path.extname.delete(".")),
                                disposition: "inline"
      end

      @output_relative_path = relative_output_path(@output_path)
    end

    def create
      @composition = composition
      @render_id = SecureRandom.hex(8)
      @output_path = output_path(@render_id)
      @output_path.dirname.mkpath
      @output_relative_path = relative_output_path(@output_path)

      RenderStore.create!(
        id: @render_id,
        composition_id: @composition.id,
        total_frames: @composition.duration_in_frames,
        output_path: @output_path
      )
      start_render(@render_id, @composition.id, request.base_url, @output_path.to_s, frames_dir(@render_id).to_s,
                   preview_props, render_options)

      render status: :accepted
    end

    def cancel
      RenderStore.cancel!(params[:id])
      head :accepted
    end

    private

    def output_path(render_id)
      ext = AnimateIt::VideoRenderer::EXTENSION_FOR_FORMAT.fetch(@composition.output_format) || "mp4"
      Rails.root.join("tmp/animate_it/renders/#{render_id}.#{ext}")
    end

    def frames_dir(render_id)
      Rails.root.join("tmp/animate_it/renders/#{render_id}_frames")
    end

    def relative_output_path(path)
      path&.relative_path_from(Rails.root)&.to_s
    end

    def render_options
      {
        "concurrency" => env_with_legacy("ANIMATE_IT_RENDER_CONCURRENCY", "RAILS_MOTION_RENDER_CONCURRENCY", "3").to_i,
        "starts_per_second" => env_with_legacy("ANIMATE_IT_RENDER_STARTS_PER_SECOND",
                                               "RAILS_MOTION_RENDER_STARTS_PER_SECOND", "2").to_f
      }
    end

    # Prefer the new ANIMATE_IT_* name; fall back to the legacy RAILS_MOTION_*
    # name for one release so existing setups don't break, then the default.
    def env_with_legacy(new_key, legacy_key, default)
      ENV[new_key].presence || ENV[legacy_key].presence || default
    end

    def start_render(render_id, composition_id, host, output_path, frame_dir, props, options)
      Thread.new do
        Rails.application.executor.wrap do
          RenderJob.perform_now(render_id, composition_id, host, output_path, frame_dir, props, options)
        end
      end
    end
  end
end
