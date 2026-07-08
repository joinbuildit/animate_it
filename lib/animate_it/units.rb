module AnimateIt
  module Units
    module_function

    # Time-string regex: accepts "1s", "1.5s", "300ms", "2m", "1m30s".
    TIME_STRING = /\A(?:(\d+)m)?\s*(\d+(?:\.\d+)?)?\s*(s|ms)?\z/

    def frames(value, fps:)
      case value
      when ActiveSupport::Duration
        (value.to_f * fps).round
      when FrameDuration, Numeric
        value.to_i
      when String
        seconds = parse_time_string(value)
        raise ArgumentError, "Cannot convert #{value.inspect} to frames" if seconds.nil?

        (seconds * fps).round
      when nil
        nil
      else
        raise ArgumentError, "Cannot convert #{value.inspect} to frames"
      end
    end

    # Parses "1s", "1.5s", "300ms", "2m", "1m30s" into seconds (Float).
    def parse_time_string(str)
      m = str.strip.match(TIME_STRING)
      return nil if m.nil? || (m[1].nil? && m[2].nil?)

      minutes = m[1].to_i
      number = m[2].to_f
      unit = m[3] || "s"
      base = unit == "ms" ? number / 1000.0 : number
      (minutes * 60) + base
    end
  end
end
