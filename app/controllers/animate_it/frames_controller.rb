module AnimateIt
  class FramesController < ApplicationController
    layout false
    skip_forgery_protection

    def show
      @composition = composition
      @frame = params[:frame].to_i
      @content = @composition.render_frame(view_context, frame: @frame, props: preview_props)
      # `?only=body` returns just the .animate-it-frame element (no <head> /
      # stylesheets) so the studio can morph it into a persistent document
      # instead of reloading the whole frame doc. The full-document render is
      # what the Playwright render pipeline uses — left untouched.
      render(:fragment) if params[:only] == "body"
    end

    def filmstrip
      @composition = composition
      @props = preview_props
    end

    def player
      @composition = composition
      @props = preview_props
      @track_document = @composition.track_document(props: @props)
      TrackDocumentSchema.validate!(@track_document)
    end
  end
end
