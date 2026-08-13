module AnimateIt
  class PlayerManifest
    VERSION = 1

    def initialize(composition)
      @composition = composition
    end

    def as_json(*)
      @composition.chapters.validate!
      {
        "version" => VERSION,
        "id" => @composition.id,
        "width" => @composition.width,
        "height" => @composition.height,
        "fps" => @composition.fps,
        "duration" => @composition.duration_in_frames,
        "chapters" => @composition.chapters.as_json,
        "playback" => @composition.public_player_options.transform_keys { |key| camelize(key) }
      }
    end

    private

    def camelize(key)
      key.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
    end
  end
end
