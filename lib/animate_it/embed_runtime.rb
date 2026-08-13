module AnimateIt
  module EmbedRuntime
    module_function

    def javascript
      @javascript ||= File.read(File.expand_path("embed_runtime/embed.js", __dir__)).freeze
    end

    def stylesheet
      EmbedStyles.source
    end
  end
end
