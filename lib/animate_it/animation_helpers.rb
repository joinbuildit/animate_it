module AnimateIt
  module AnimationHelpers
    def animation_vars(**properties)
      Style.vars(**properties)
    end

    def fade(start_frame, end_frame, from: 0, to: 1, easing: :ease_out)
      interpolate_range([start_frame, end_frame], [from, to], easing:)
    end

    def slide(start_frame, end_frame, from: 16, to: 0, easing: :ease_out)
      interpolate_range([start_frame, end_frame], [from, to], easing:)
    end

    def press(start_frame, middle_frame, end_frame, from: 1.0, to: 1.08, easing: :ease_out)
      interpolate_range([start_frame, middle_frame, end_frame], [from, to, from], easing:)
    end

    def pulse(start_frame, middle_frame, end_frame, from:, to:, back_to: from, easing: :ease_out)
      interpolate_range([start_frame, middle_frame, end_frame], [from, to, back_to], easing:)
    end

    def interpolate_range(input_range, output_range, easing: :ease_out)
      interpolate(
        local_frame,
        input_range,
        output_range,
        easing:,
        extrapolate_left: :clamp,
        extrapolate_right: :clamp
      ).round(4)
    end

    def loop_frame(duration, frame: local_frame)
      frame % AnimateIt::Units.frames(duration, fps:)
    end

    def loop_iteration(duration, frame: local_frame)
      frame / AnimateIt::Units.frames(duration, fps:)
    end

    def freeze_frame(frozen_frame, active: true)
      active.respond_to?(:call) && !active.call(local_frame) ? local_frame : frozen_frame
    end

    def act_local(beat_name)
      local_frame - composition_class.beats.fetch(beat_name).start_frame
    end

    def at_act(beat_name, ranges, values, easing: :ease_out)
      interpolate(
        act_local(beat_name),
        ranges,
        values,
        easing:,
        extrapolate_left: :clamp,
        extrapolate_right: :clamp
      ).round(4)
    end

    def at_global(ranges, values, easing: :ease_out)
      interpolate(
        local_frame,
        ranges,
        values,
        easing:,
        extrapolate_left: :clamp,
        extrapolate_right: :clamp
      ).round(4)
    end

    def beat_frame(beat_name)
      composition_class.beats.fetch(beat_name).start_frame
    end

    def beat_end(beat_name)
      beat = composition_class.beats.fetch(beat_name)
      beat.start_frame + beat.duration_frames
    end

    def beat_range(beat_name)
      beat = composition_class.beats.fetch(beat_name)
      [beat.start_frame, beat.start_frame + beat.duration_frames]
    end
  end
end
