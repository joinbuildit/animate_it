module AnimateIt
  module Style
    module_function

    def build(*rules, **properties)
      property_rules = properties.filter_map do |property, value|
        next if value.nil?

        "#{property.to_s.tr("_", "-")}: #{value}"
      end

      (rules.flatten.compact + property_rules).join("; ")
    end

    def vars(**properties)
      properties.filter_map do |property, value|
        next if value.nil?

        "--#{property.to_s.tr("_", "-")}: #{value}"
      end.join("; ")
    end
  end
end
