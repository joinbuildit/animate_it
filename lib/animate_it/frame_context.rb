module AnimateIt
  FrameContext = Data.define(
    :composition,
    :props,
    :frame,
    :local_frame,
    :fps,
    :duration_in_frames,
    :width,
    :height,
    :segment
  ) do
    def progress(duration_frames: nil)
      total = duration_frames || segment&.duration_frames || duration_in_frames
      return 0.0 if total.to_i <= 1

      local_frame.to_f / (total - 1)
    end

    def interpolate(input, input_range, output_range, **)
      Timing.interpolate(input, input_range, output_range, **)
    end

    def spring(**)
      Timing.spring(frame: local_frame, fps:, **)
    end
  end
end
