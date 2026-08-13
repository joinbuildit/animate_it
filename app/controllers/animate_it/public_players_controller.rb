module AnimateIt
  # The only production-accessible AnimateIt surface. Compositions must opt in
  # explicitly with `public_player!`; all Studio and rendering controllers keep
  # their local-environment guard.
  class PublicPlayersController < ApplicationController
    AUDIO_BASE = Rails.root.join("app/audio").freeze

    layout false
    skip_before_action :ensure_local_environment
    before_action :ensure_public_player

    def show
      @props = {}
      @track_document = composition.track_document
      TrackDocumentSchema.validate!(@track_document)
      @player_manifest = composition.player_manifest
      @audio_segments = audio_segments
      @public_player = true
      @embedded_player = params[:embedded] == "1"
      @host_navigation = params[:host_navigation] == "1"
      @public_player_options = composition.public_player_options.merge(autoplay: false) if @embedded_player
      @public_player_options ||= composition.public_player_options
      render "animate_it/frames/player"
    end

    def audio
      segment = audio_segments[params[:index].to_i]
      return head :not_found unless segment

      file_path = resolve_audio_path(segment.source[:path])
      return head :not_found unless file_path

      serve_with_byte_ranges(file_path)
    end

    private

    def ensure_public_player
      head :not_found unless composition.public_player? && composition.client_driven?
    end

    def audio_segments
      @audio_segments ||= composition.timeline.segments.select { |segment| segment.kind == :audio }
    end

    def public_audio_path(index)
      animate_it_path("/public/compositions/#{composition.id}/audio/#{index}")
    end
    helper_method :public_audio_path

    def serve_with_byte_ranges(file_path)
      status, headers, body = Rack::Files.new(file_path.dirname.to_s).serving(request, file_path.to_s)
      headers["content-type"] = Mime::Type.lookup_by_extension(file_path.extname.delete(".")).to_s
      headers["content-disposition"] = "inline"
      headers["accept-ranges"] = "bytes"
      self.status = status
      self.response_body = body
      headers.each { |key, value| response.headers[key] = value }
    end

    def resolve_audio_path(path)
      return if path.blank?

      base = AUDIO_BASE.realpath
      candidate = Pathname.new(path)
      candidate = base.join(candidate) unless candidate.absolute?
      resolved = candidate.realpath
      resolved if resolved.to_s.start_with?("#{base}#{File::SEPARATOR}")
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end
  end
end
