module AnimateIt
  module Easing
    module_function

    def resolve(easing)
      return easing if easing.respond_to?(:call)

      case easing
      when nil, :linear
        method(:linear)
      when :ease_in
        method(:ease_in)
      when :ease_out
        method(:ease_out)
      when :ease_in_out
        method(:ease_in_out)
      else
        raise ArgumentError, "Unknown easing: #{easing.inspect}"
      end
    end

    def linear(progress)
      progress
    end

    def ease_in(progress)
      progress * progress
    end

    def ease_out(progress)
      1 - ((1 - progress) * (1 - progress))
    end

    def ease_in_out(progress)
      return 2 * progress * progress if progress < 0.5

      1 - ((((-2 * progress) + 2)**2) / 2.0)
    end
  end
end
