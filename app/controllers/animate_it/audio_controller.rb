module AnimateIt
  class AudioController < ApplicationController
    AUDIO_BASE = Rails.root.join("app/audio").freeze

    def show
      audio_segments = composition.timeline.segments.select { |seg| seg.kind == :audio }
      segment = audio_segments[params[:index].to_i]
      return head :not_found unless segment

      file_path = resolve_audio_path(segment.source[:path])
      return head :not_found unless file_path && File.file?(file_path)

      serve_with_byte_ranges(file_path)
    end

    private

    # send_file ignores Range headers, and browsers refuse to seek media
    # served without byte-range support — every currentTime seek snaps back
    # to 0:00, so the Studio player restarts clips from the beginning.
    # Rack::Files implements range semantics (Accept-Ranges, 206/416).
    def serve_with_byte_ranges(file_path)
      status, headers, body = Rack::Files.new(File.dirname(file_path)).serving(request, file_path)
      headers["content-type"] = Mime::Type.lookup_by_extension(File.extname(file_path).delete(".")).to_s
      headers["content-disposition"] = "inline"
      headers["accept-ranges"] = "bytes"
      self.status = status
      self.response_body = body
      headers.each { |key, value| response.headers[key] = value }
    end

    def resolve_audio_path(path)
      return nil if path.blank?

      pathname = Pathname.new(path)
      return pathname.to_s if pathname.absolute? && pathname.realpath.to_s.start_with?(AUDIO_BASE.to_s)

      candidate = AUDIO_BASE.join(path).expand_path
      return nil unless candidate.to_s.start_with?(AUDIO_BASE.to_s)

      candidate.to_s
    end
  end
end
