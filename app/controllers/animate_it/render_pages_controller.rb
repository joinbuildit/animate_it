module AnimateIt
  class RenderPagesController < ApplicationController
    layout false
    skip_before_action :ensure_local_environment
    skip_forgery_protection
    before_action :ensure_internal_rendering

    def show
      ticket = RenderTicketStore.read(params[:token])
      return head :not_found unless ticket

      @composition = AnimateIt.registry.fetch(ticket.fetch("composition"))
      return head :not_found unless @composition.client_driven?

      @props = ticket.fetch("props").deep_symbolize_keys
      @track_document = @composition.track_document(props: @props)
      TrackDocumentSchema.validate!(@track_document)
      @player_manifest = @composition.player_manifest
      @embedded_player = false
      @host_navigation = false
      @public_player = false
      render "animate_it/frames/player"
    end

    private

    def ensure_internal_rendering
      head :not_found unless AnimateIt.config.internal_rendering?
    end
  end
end
