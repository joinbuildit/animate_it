module AnimateIt
  class AudioController < ApplicationController
    AUDIO_BASE = Rails.root.join("app/audio").freeze

    def show
      audio_segments = composition.timeline.segments.select { |seg| seg.kind == :audio }
      segment = audio_segments[params[:index].to_i]
      return head :not_found unless segment

      file_path = resolve_audio_path(segment.source[:path])
      return head :not_found unless file_path && File.file?(file_path)

      send_file file_path, type: Mime::Type.lookup_by_extension(File.extname(file_path).delete(".")),
                           disposition: "inline"
    end

    private

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
