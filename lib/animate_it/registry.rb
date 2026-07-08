module AnimateIt
  class Registry
    def initialize
      @compositions = {}
    end

    def register(composition_class)
      id = composition_class.id
      raise ArgumentError, "Composition #{composition_class.name} must declare an id" if id.blank?

      @compositions[id] = composition_class
    end

    def fetch(id)
      @compositions.fetch(id) do
        raise CompositionNotFoundError, "No AnimateIt composition registered for #{id.inspect}"
      end
    end

    def all
      @compositions.values.sort_by(&:id)
    end

    # Drop every registration. Used by `AnimateIt.reload_compositions!` on
    # dev-mode reload so renamed/removed composition ids don't linger.
    def reset!
      @compositions.clear
    end
  end
end
