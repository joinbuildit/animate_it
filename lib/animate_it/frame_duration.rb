module AnimateIt
  FrameDuration = Data.define(:value) do
    delegate :to_i, to: :value
  end
end

unless Numeric.method_defined?(:frames)
  class Numeric
    def frames
      AnimateIt::FrameDuration.new(to_i)
    end
  end
end
