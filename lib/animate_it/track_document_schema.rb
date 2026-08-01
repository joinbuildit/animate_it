module AnimateIt
  # Validates the server/browser track-document boundary before embedding it.
  module TrackDocumentSchema
    CURRENT_VERSION = 2
    SUPPORTED_VERSIONS = [1, CURRENT_VERSION].freeze

    module_function

    def validate!(document)
      data = document.respond_to?(:as_json) ? document.as_json : document
      raise Error, "AnimateIt track document must be a JSON object" unless data.is_a?(Hash)

      version = data["v"]
      unless SUPPORTED_VERSIONS.include?(version)
        raise Error,
              "Unsupported AnimateIt track schema #{version.inspect}; " \
              "supported versions are #{SUPPORTED_VERSIONS.join(", ")}"
      end

      validate_positive_number!(data, "fps")
      validate_positive_integer!(data, "duration")
      validate_hash!(data, "groups")
      validate_hash!(data, "texts")
      validate_array!(data, "layers")
      validate_v2!(data) if version == CURRENT_VERSION
      data
    end

    def validate_v2!(data)
      validate_hash!(data, "groupSelectors")
      validate_hash!(data, "textSelectors")
      validate_selector_keys!(data["groups"], data["groupSelectors"], "group")
      validate_selector_keys!(data["texts"], data["textSelectors"], "text")
    end
    private_class_method :validate_v2!

    def validate_selector_keys!(tracks, selectors, kind)
      extra = selectors.keys - tracks.keys
      return if extra.empty?

      raise Error, "AnimateIt v2 #{kind} selectors reference missing tracks: #{extra.join(", ")}"
    end
    private_class_method :validate_selector_keys!

    def validate_positive_number!(data, key)
      value = data[key]
      return if value.is_a?(Numeric) && value.positive?

      raise Error, "AnimateIt track document #{key} must be a positive number"
    end
    private_class_method :validate_positive_number!

    def validate_positive_integer!(data, key)
      value = data[key]
      return if value.is_a?(Integer) && value.positive?

      raise Error, "AnimateIt track document #{key} must be a positive integer"
    end
    private_class_method :validate_positive_integer!

    def validate_hash!(data, key)
      raise Error, "AnimateIt track document #{key} must be an object" unless data[key].is_a?(Hash)
    end
    private_class_method :validate_hash!

    def validate_array!(data, key)
      raise Error, "AnimateIt track document #{key} must be an array" unless data[key].is_a?(Array)
    end
    private_class_method :validate_array!
  end
end
