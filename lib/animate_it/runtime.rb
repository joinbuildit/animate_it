module AnimateIt
  # The client-side playback runtime, inlined into the player page via
  # `javascript_tag` (no asset-pipeline coupling).
  module Runtime
    module_function

    def source
      @source ||= File.read(File.expand_path("runtime/runtime.js", __dir__)).freeze
    end
  end
end
