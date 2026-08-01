module AnimateIt
  # Drives a composition through every Output it declared, writing each one
  # to its absolute repo-relative path. Outputs covering the same frame range
  # share one ordered browser capture; each format still gets its own encoder.
  module AssetRenderer
    module_function

    def render_composition(composition, host:, on_progress: nil, frame_range: nil)
      raise Error, "Composition #{composition.id} has no `outputs do ... end`" if composition.outputs.empty?

      capture_dirs = {}
      composition.outputs.map do |output|
        effective_range = effective_range_for(output, frame_range)
        next if effective_range == :skip

        capture_key = capture_key_for(composition, effective_range)
        frames_dir = capture_dirs[capture_key]
        reuse_captured_frames = capture_dirs.key?(capture_key)
        frames_dir ||= frames_dir_for(composition, capture_key, primary: capture_dirs.empty?)
        capture_dirs[capture_key] = frames_dir

        render_output(
          composition,
          output,
          host:,
          on_progress:,
          frame_range: effective_range,
          frames_dir:,
          reuse_captured_frames:
        )
      end
    end

    def render_output(composition, output, host:, on_progress: nil, frame_range: nil, frames_dir: nil,
                      reuse_captured_frames: false)
      effective_range = effective_range_for(output, frame_range)
      return nil if effective_range == :skip

      destination = output.absolute_path
      FileUtils.mkdir_p(destination.dirname)

      renderer = VideoRenderer.new(
        composition: composition,
        host: host,
        output_path: destination,
        format: output.format,
        frames_dir:
      )

      renderer.render(frame_range: effective_range, on_progress:, reuse_captured_frames:)
      destination
    end

    def capture_key_for(composition, frame_range)
      range = frame_range || (0...composition.duration_in_frames)
      [range.first, range.last]
    end

    def frames_dir_for(composition, capture_key, primary:)
      base = Rails.root.join("tmp/animate_it/#{composition.id}")
      return base if primary

      start_frame, end_frame = capture_key
      base.join("captures/#{start_frame}-#{end_frame}")
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
