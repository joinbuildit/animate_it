module AnimateIt
  # ----- Per-animatable property declaration ----------------------------
  # One CSS-driven animation slot on a `data-anim="..."` element. The
  # framework turns these into both:
  #   1. CSS variables on the wrapper (set per frame at render time), and
  #   2. CSS rules of the form `[data-anim="name"] { property: var(--…); }`
  #      injected into the rendered HTML so the HAML doesn't need a `:css`
  #      block to bind variables to selectors.
  AnimationProperty = Data.define(:css_property, :var_suffix, :unit, :default, :keyframes_to_values) do
    def var_name(animatable_name)
      "--#{animatable_name.to_s.tr("_", "-")}-#{var_suffix.to_s.tr("_", "-")}"
    end
  end

  AnimatableElement = Data.define(:name, :properties)

  class AnimationSet
    attr_reader :elements

    def initialize
      @elements = {}
    end

    def add(name, builder_block)
      builder = AnimatableBuilder.new(name)
      builder.instance_eval(&builder_block) if builder_block
      @elements[name.to_sym] = AnimatableElement.new(name: name.to_sym, properties: builder.properties)
    end

    # Compute the per-frame CSS variable hash for the entire set, given the
    # current local_frame plus a beats registry to resolve symbolic ranges.
    def vars_for(scene)
      vars = {}
      @elements.each_value do |element|
        element.properties.each do |prop|
          value = compute_value(prop, scene)
          vars[var_key(element.name, prop.var_suffix)] = format_value(value, prop.unit)
        end
      end
      vars
    end

    # Emit `<style>` block content with `[data-anim="name"] { … }` rules.
    # Generated once per AnimationSet (memoized).
    def css_rules
      @css_rules ||= @elements.values.map { |element| rules_for(element) }.join("\n")
    end

    private

    def var_key(name, suffix)
      :"#{name}_#{suffix}"
    end

    def rules_for(element)
      transforms = []
      direct_props = []
      element.properties.each do |prop|
        var_ref = "var(#{prop.var_name(element.name)}, #{format_default(prop.default, prop.unit)})"
        case prop.css_property
        when :translate_y then transforms << "translateY(#{var_ref})"
        when :translate_x then transforms << "translateX(#{var_ref})"
        when :scale       then transforms << "scale(#{var_ref})"
        when :rotate      then transforms << "rotate(#{var_ref})"
        else
          direct_props << "#{prop.css_property.to_s.tr("_", "-")}: #{var_ref};"
        end
      end
      direct_props << "transform: #{transforms.join(" ")};" if transforms.any?
      # HTML data attribute convention is hyphens, not underscores.
      selector_name = element.name.to_s.tr("_", "-")
      "[data-anim=\"#{selector_name}\"] { #{direct_props.join(" ")} transition: none; will-change: opacity, transform; }"
    end

    def compute_value(prop, scene)
      keyframes = prop.keyframes_to_values.call(scene)
      frames = keyframes.keys
      values = keyframes.values
      scene.interpolate(scene.local_frame, frames, values, easing: :ease_out, extrapolate_left: :clamp,
                                                           extrapolate_right: :clamp).round(4)
    end

    def format_value(value, unit)
      unit ? "#{value}#{unit}" : value
    end

    def format_default(default, unit)
      unit ? "#{default}#{unit}" : default
    end
  end

  # ----- Per-element DSL ------------------------------------------------
  class AnimatableBuilder
    attr_reader :properties

    def initialize(name)
      @name = name
      @properties = []
    end

    # Opacity 0→1 over a frame range (or beat name, or keyframe hash).
    def fade(during: nil, in: nil, out: nil, keyframes: nil, from: 0, to: 1)
      add_property(:opacity, :opacity, nil, from,
                   build_keyframes(during, binding.local_variable_get(:in), out, keyframes, from: from, to: to))
    end

    # Vertical translate `from`→`to` over a frame range.
    def slide(during: nil, keyframes: nil, from: 16, to: 0, axis: :y, unit: "px")
      css = axis == :y ? :translate_y : :translate_x
      add_property(css, css, unit, from, build_keyframes(during, nil, nil, keyframes, from: from, to: to))
    end

    def scale(during: nil, keyframes: nil, from: 1, to: 1.05)
      add_property(:scale, :scale, nil, from, build_keyframes(during, nil, nil, keyframes, from: from, to: to))
    end

    # Generic CSS property — when the named helpers (fade/slide/scale) don't
    # cover what you need (max-height, height, color, etc.).
    def css(property, from:, during: nil, keyframes: nil, to: nil, unit: nil)
      kf = build_keyframes(during, nil, nil, keyframes, from: from, to: to.nil? ? from : to)
      add_property(property, property, unit, from, kf)
    end

    private

    def add_property(css_property, var_suffix, unit, default, keyframes_proc)
      @properties << AnimationProperty.new(
        css_property: css_property,
        var_suffix: var_suffix,
        unit: unit,
        default: default,
        keyframes_to_values: keyframes_proc
      )
    end

    # Returns a Proc that, given a Scene with access to the composition's
    # beats registry, resolves any symbolic ranges (beat names) into a
    # frame→value Hash suitable for interpolation.
    def build_keyframes(during, in_range, out_range, keyframes_arg, from:, to:)
      lambda do |scene|
        if keyframes_arg
          resolve_keyframe_hash(keyframes_arg, scene)
        elsif during
          range = resolve_range(during, scene)
          { range.first => from, range.last => to }
        elsif in_range && out_range
          a = resolve_range(in_range, scene)
          b = resolve_range(out_range, scene)
          { a.first => from, a.last => to, b.first => to, b.last => from }
        elsif in_range
          a = resolve_range(in_range, scene)
          { a.first => from, a.last => to }
        elsif out_range
          b = resolve_range(out_range, scene)
          { b.first => to, b.last => from }
        else
          { 0 => from }
        end
      end
    end

    def resolve_range(input, scene)
      case input
      when Range
        Range.new(resolve_frame(input.first, scene), resolve_frame(input.last, scene))
      when Symbol
        scene.composition_class.beats.fetch(input).range
      else
        raise Error, "Don't know how to resolve range #{input.inspect}"
      end
    end

    def resolve_keyframe_hash(hash, scene)
      hash.each_with_object({}) do |(k, v), out|
        out[resolve_frame(k, scene)] = v
      end
    end

    def resolve_frame(value, scene)
      case value
      when Integer then value
      when Float then value.to_i
      when Symbol then scene.composition_class.beats.fetch(value).start_frame
      else
        AnimateIt::Units.frames(value, fps: scene.fps).to_i
      end
    end
  end
end
