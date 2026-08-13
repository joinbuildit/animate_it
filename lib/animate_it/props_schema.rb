require "json"
require "uri"

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

    # Strict resolution for controller-driven image rendering. Studio and CLI
    # callers intentionally continue using the permissive `resolve` method.
    def resolve_for_render(input, render_origin:, asset_origins: AnimateIt.config.render_asset_origins)
      unless input.is_a?(Hash) && input.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
        raise RenderPropsError, "Rendered props must be a hash with string or symbol keys"
      end

      values = input.transform_keys(&:to_sym)
      unknown = values.keys - fields.map(&:name)
      raise RenderPropsError, "Unknown render props: #{unknown.join(", ")}" if unknown.any?

      resolved = defaults.merge(values)
      fields.each do |definition|
        value = resolved[definition.name]
        validate_type!(definition, value)
        validate_string_size!(definition, value)
        validate_asset!(definition, value, render_origin:, asset_origins:)
      end

      serialized = JSON.generate(resolved)
      if serialized.bytesize > AnimateIt.config.render_props_max_bytes
        raise RenderPropsError,
              "Rendered props exceed #{AnimateIt.config.render_props_max_bytes} bytes"
      end

      resolved
    rescue JSON::GeneratorError => e
      raise RenderPropsError, "Rendered props are not JSON-safe: #{e.message}"
    end

    private

    def field(name, type, default:, **options)
      fields << Field.new(name.to_sym, type, default, options)
    end

    def validate_type!(definition, value)
      valid = case definition.type
              when :string, :color, :asset then value.nil? || value.is_a?(String)
              when :integer then value.nil? || value.is_a?(Integer)
              when :number then value.nil? || (value.is_a?(Numeric) && (!value.respond_to?(:finite?) || value.finite?))
              when :boolean then value.nil? || value == true || value == false
              else false
              end
      return if valid

      raise RenderPropsError, "Render prop #{definition.name.inspect} must be a #{definition.type}"
    end

    def validate_string_size!(definition, value)
      return unless value.is_a?(String)
      return if value.bytesize <= AnimateIt.config.render_prop_string_max_bytes

      raise RenderPropsError,
            "Render prop #{definition.name.inspect} exceeds #{AnimateIt.config.render_prop_string_max_bytes} bytes"
    end

    def validate_asset!(definition, value, render_origin:, asset_origins:)
      return unless definition.type == :asset && value.present?

      uri = URI.parse(value)
      return if uri.scheme.nil? && uri.host.nil? && !value.start_with?("//")

      allowed = [render_origin, *asset_origins].filter_map { |origin| normalized_origin(origin) }
      return if allowed.include?(normalized_origin(uri))

      raise RenderPropsError, "Render asset #{definition.name.inspect} must use an allowed origin or relative URL"
    rescue URI::InvalidURIError
      raise RenderPropsError, "Render asset #{definition.name.inspect} is not a valid URL"
    end

    def normalized_origin(value)
      uri = value.is_a?(URI) ? value : URI.parse(value.to_s)
      return unless %w[http https].include?(uri.scheme) && uri.host.present?

      default_port = uri.scheme == "https" ? 443 : 80
      port = uri.port == default_port ? nil : uri.port
      port_suffix = port ? ":#{port}" : nil
      "#{uri.scheme}://#{uri.host.downcase}#{port_suffix}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
