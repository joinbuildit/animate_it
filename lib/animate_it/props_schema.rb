module AnimateIt
  class PropsSchema
    Field = Data.define(:name, :type, :default, :options)

    attr_reader :fields

    def initialize
      @fields = []
    end

    def string(name, default: nil, **)
      field(name, :string, default:, **)
    end

    def color(name, default: nil, **)
      field(name, :color, default:, **)
    end

    def asset(name, default: nil, **)
      field(name, :asset, default:, **)
    end

    def integer(name, default: nil, **)
      field(name, :integer, default:, **)
    end

    def number(name, default: nil, **)
      field(name, :number, default:, **)
    end

    def boolean(name, default: nil, **)
      field(name, :boolean, default:, **)
    end

    def defaults
      fields.to_h { |field| [field.name, field.default] }
    end

    def resolve(input)
      defaults.merge(input.transform_keys(&:to_sym))
    end

    private

    def field(name, type, default:, **options)
      fields << Field.new(name.to_sym, type, default, options)
    end
  end
end
