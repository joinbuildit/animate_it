module AnimateIt
  # Drives a composition through every Output it declared, writing each one
  # to its absolute repo-relative path. One VideoRenderer per output (cheap —
  # frames are captured once per output even when the same composition has
  # several formats, because each format wants a different ffmpeg encode).
  module AssetRenderer
    module_function

    def render_composition(composition, host:, on_progress: nil, frame_range: nil)
      raise Error, "Composition #{composition.id} has no `outputs do ... end`" if composition.outputs.empty?

      composition.outputs.map do |output|
        render_output(composition, output, host: host, on_progress: on_progress, frame_range: frame_range)
      end
    end

    def render_output(composition, output, host:, on_progress: nil, frame_range: nil)
      effective_range = effective_range_for(output, frame_range)
      return nil if effective_range == :skip

      destination = output.absolute_path
      FileUtils.mkdir_p(destination.dirname)

      renderer = VideoRenderer.new(
        composition: composition,
        host: host,
        output_path: destination,
        format: output.format
      )

      renderer.render(frame_range: effective_range, on_progress: on_progress)
      destination
    end

    # A still PNG output always renders its declared single frame; if the
    # caller-supplied range excludes that frame, skip the output entirely.
    # Animated outputs use the caller's range when provided, otherwise
    # render the full composition.
    def effective_range_for(output, frame_range)
      if output.still?
        return :skip if frame_range && !frame_range.cover?(output.frame)

        output.frame..output.frame
      else
        frame_range
      end
    end
  end
end
