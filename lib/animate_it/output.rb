module AnimateIt
  # Declarative output target: one rendered file at one path.
  # `format` selects the encoder; `path` is repo-relative (joined onto
  # Rails.root by the renderer); `frame` is set for single-frame stills,
  # nil for animated outputs (the whole composition).
  Output = Struct.new(:format, :path, :frame, keyword_init: true) do
    def still?
      !frame.nil?
    end

    def absolute_path
      Rails.root.join(path.to_s)
    end
  end

  # Block DSL used inside `Composition.outputs do ... end`.
  #
  # Each method declares one Output. Two ways to call each format:
  #
  #   # explicit path
  #   mp4 to: "app/assets/images/pages/product/screener-hero.mp4"
  #
  #   # convention-based path (composition declared `assets_dir` + `output_basename`)
  #   mp4
  #   webm
  #   gif
  #   png frame: 0       # → <basename>-first.png
  class OutputsBuilder
    attr_reader :outputs

    def initialize(assets_dir: nil, basename: nil)
      @outputs = []
      @assets_dir = assets_dir
      @basename = basename
    end

    Composition::SUPPORTED_OUTPUT_FORMATS.each do |fmt|
      define_method(fmt) do |to: nil, frame: nil|
        path = to || conventional_path(fmt, frame)
        @outputs << Output.new(format: fmt, path: path, frame: frame)
      end
    end

    private

    def conventional_path(fmt, frame)
      if @assets_dir.blank? || @basename.blank?
        raise ArgumentError,
              "Pass `to:` or declare `assets_dir`/`output_basename` on the composition"
      end

      ext = AnimateIt::VideoRenderer::EXTENSION_FOR_FORMAT[fmt] || fmt.to_s
      suffix = frame&.zero? ? "-first" : nil # frame is nil for animated outputs
      File.join(@assets_dir, "#{@basename}#{suffix}.#{ext}")
    end
  end
end
