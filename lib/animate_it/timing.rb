module AnimateIt
  module Timing
    module_function

    def interpolate(input, input_range, output_range, easing: :linear, extrapolate_left: :extend,
                    extrapolate_right: :extend)
      unless input_range.size == output_range.size
        raise ArgumentError,
              "input_range and output_range must have the same size"
      end
      raise ArgumentError, "interpolation needs at least two points" if input_range.size < 2

      validate_extrapolation!(extrapolate_left)
      validate_extrapolation!(extrapolate_right)

      left_index = segment_index(input, input_range)
      right_index = left_index + 1
      input_start = input_range[left_index]
      input_end = input_range[right_index]

      if input < input_range.first
        return output_range.first if extrapolate_left == :clamp
        return input if extrapolate_left == :identity
      end

      if input > input_range.last
        return output_range.last if extrapolate_right == :clamp
        return input if extrapolate_right == :identity
      end
      return output_range[left_index] if input_end == input_start

      progress = (input - input_start).to_f / (input_end - input_start)
      eased = Easing.resolve(easing).call(progress)

      output_start = output_range[left_index]
      output_end = output_range[right_index]

      output_start + ((output_end - output_start) * eased)
    end

    def spring(frame:, fps:, from: 0.0, to: 1.0, stiffness: 100.0, damping: 10.0, mass: 1.0)
      seconds = [frame.to_f / fps, 0].max
      angular_frequency = Math.sqrt(stiffness / mass)
      decay = Math.exp((-damping / (2 * mass)) * seconds)
      progress = 1 - (decay * Math.cos(angular_frequency * seconds))

      from + ((to - from) * progress)
    end

    def segment_index(input, input_range)
      return 0 if input <= input_range.first

      index = input_range.each_cons(2).find_index { |left, right| input.between?(left, right) }
      index || (input_range.size - 2)
    end

    def validate_extrapolation!(mode)
      return if %i[clamp extend identity].include?(mode)

      raise ArgumentError, "Unsupported extrapolation mode: #{mode.inspect}"
    end
  end
end
