module AnimateIt
  class RenderStore
    CHANNEL = "animate_it_renders".freeze
    TARGET = "animate_it_renders".freeze

    Render = Data.define(
      :id,
      :composition_id,
      :status,
      :current_frame,
      :total_frames,
      :output_path,
      :error
    ) do
      def progress_percent
        return 0 if total_frames.to_i.zero?

        ((current_frame.to_f / total_frames) * 100).round
      end
    end

    class << self
      def create!(id:, composition_id:, total_frames:, output_path:)
        render = nil
        synchronize do
          render = Render.new(id, composition_id, :queued, 0, total_frames, output_path.to_s, nil)
          renders[id] = render
        end
        broadcast_append(render)
      end

      def start!(id)
        update!(id, status: :rendering)
      end

      def progress!(id, frame:, total_frames:)
        update!(id, status: :rendering, current_frame: frame, total_frames:)
      end

      def complete!(id)
        render = fetch(id)
        update!(id, status: :complete, current_frame: render.total_frames)
      end

      def fail!(id, error)
        update!(id, status: :failed, error: error.message)
      end

      def cancel!(id)
        update!(id, status: :cancelled, error: "Cancelled by user")
      end

      def cancelled?(id)
        fetch(id).status == :cancelled
      rescue KeyError
        true
      end

      def all
        synchronize { renders.values.reverse }
      end

      def fetch(id)
        synchronize { renders.fetch(id) }
      end

      # nil-tolerant lookup — returns nil when the render isn't registered
      # (e.g. server restart cleared the in-memory store but a tab still
      # holds the old render id).
      def find(id)
        synchronize { renders[id] }
      end

      def broadcast_replace(render)
        return unless defined?(Turbo::StreamsChannel)

        Turbo::StreamsChannel.broadcast_replace_to(
          CHANNEL,
          target: row_id(render.id),
          html: render_row(render)
        )
      end

      def broadcast_append(render)
        return unless defined?(Turbo::StreamsChannel)

        Turbo::StreamsChannel.broadcast_append_to(
          CHANNEL,
          target: TARGET,
          html: render_row(render)
        )
      end

      def html
        <<~HTML
          <div id="#{TARGET}" class="animate-it-renders-list">
            #{render_rows}
          </div>
        HTML
      end

      private

      def update!(id, **attributes)
        updated = synchronize do
          render = renders.fetch(id)
          renders[id] = Render.new(
            id,
            attributes.fetch(:composition_id, render.composition_id),
            attributes.fetch(:status, render.status),
            attributes.fetch(:current_frame, render.current_frame),
            attributes.fetch(:total_frames, render.total_frames),
            attributes.fetch(:output_path, render.output_path),
            attributes.fetch(:error, render.error)
          )
          renders[id]
        end
        broadcast_replace(updated)
      end

      def render_row(render)
        output = render.output_path.to_s
        link = output_link(render, output)
        kill = %i[queued rendering].include?(render.status) ? kill_button(render) : ""
        error = render.error.present? ? %(<p style="color: #b91c1c;">#{ERB::Util.html_escape(render.error)}</p>) : ""

        <<~HTML
          <div id="#{row_id(render.id)}" class="animate-it-render-row">
            <strong>#{ERB::Util.html_escape(render.composition_id)}</strong>
            <span>#{ERB::Util.html_escape(render.status.to_s)}</span>
            <span>frame #{render.current_frame} / #{render.total_frames}</span>
            <progress max="100" value="#{render.progress_percent}"></progress>
            <code class="animate-it-render-path" title="#{ERB::Util.html_escape(output)}">#{ERB::Util.html_escape(output)}</code>
            #{link}
            #{kill}
            #{error}
          </div>
        HTML
      end

      def render_rows
        rows = all.map { |render| render_row(render) }.join
        return rows if rows.present?

        <<~HTML
          <p id="animate_it_renders_empty" style="color: #6b7280;">No renders yet.</p>
        HTML
      end

      def row_id(render_id)
        "animate_it_render_#{render_id}"
      end

      def output_link(render, output)
        return "" unless %i[complete cancelled].include?(render.status)
        return "" unless File.exist?(output)

        %(<a href="#{AnimateIt.config.mount_path}/renders/#{render.id}?download=1" target="_blank" rel="noopener">Open MP4</a>)
      end

      def kill_button(render)
        <<~HTML
          <form action="#{AnimateIt.config.mount_path}/renders/#{render.id}/cancel" method="post" data-turbo="true">
            <input type="hidden" name="authenticity_token" value="#{ERB::Util.html_escape(authenticity_token)}">
            <button type="submit" class="button is-danger is-small">Kill render</button>
          </form>
        HTML
      end

      def authenticity_token
        ApplicationController.renderer.instance_eval { form_authenticity_token }
      rescue StandardError
        ""
      end

      def renders
        @renders ||= {}
      end

      def synchronize(&)
        mutex.synchronize(&)
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
