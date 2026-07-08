module AnimateIt
  class ApplicationController < ActionController::Base
    # Composition sidecar templates live at app/videos/<composition>/*.html.haml
    # in the host app — outside the engine's view path, so add it explicitly.
    prepend_view_path Rails.root.join("app/videos")

    # Sidecar templates routinely render host-app partials (e.g. the real
    # candidates-page _match_row.haml). Those partials reach for host helpers
    # like `user_status_style`, `full_name_hidden_display`, `add_stylesheet`,
    # etc. — and host route helpers like `expert_profile_client_matches_job_path`.
    # None of those live in the engine, so expose them all here so the engine's
    # view context matches what the host's view context offers.
    helper Rails.application.helpers
    helper Rails.application.routes.url_helpers

    protect_from_forgery with: :exception
    layout "animate_it/application"

    before_action :ensure_local_environment
    helper_method :animate_it_path, :current_user, :policy

    rescue_from AnimateIt::CompositionNotFoundError do
      head :not_found
    end

    # Host partials reach for Devise's `current_user` and Pundit's `policy(...)`
    # helpers. The engine has neither, so provide permissive null-object
    # versions for hero rendering. Hero canvases are always read-only; the
    # action buttons they incidentally render evaluate every permission to
    # false and become no-ops.
    NullPolicy = Class.new do
      def method_missing(name, *_args)
        name.to_s.end_with?("?") ? false : self
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end
    end

    private

    def ensure_local_environment
      head :not_found unless Rails.env.local?
    end

    def composition
      AnimateIt.load_compositions!
      @composition ||= AnimateIt.registry.fetch(params[:id])
    end

    def preview_props
      raw = params[:props_json].presence || params[:props].presence || "{}"
      parsed = raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h

      parsed.deep_symbolize_keys
    rescue JSON::ParserError
      {}
    end

    def animate_it_path(path)
      "#{request.script_name}#{path}"
    end

    def current_user
      nil
    end

    def policy(_subject)
      NullPolicy.new
    end
  end
end
