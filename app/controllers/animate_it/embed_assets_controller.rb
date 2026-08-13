module AnimateIt
  class EmbedAssetsController < ApplicationController
    layout false
    skip_before_action :ensure_local_environment
    skip_forgery_protection

    def javascript
      serve_asset(EmbedRuntime.javascript, "application/javascript")
    end

    def stylesheet
      serve_asset(EmbedRuntime.stylesheet, "text/css")
    end

    private

    def serve_asset(source, content_type)
      return head :not_found unless params[:version] == AnimateIt::VERSION

      expires_in 1.year, public: true, immutable: true
      response.set_header("X-Content-Type-Options", "nosniff")
      render plain: source, content_type:
    end
  end
end
