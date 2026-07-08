module AnimateIt
  module ViewHelpers
    def style(*rules, **properties)
      Style.build(*rules, **properties)
    end

    def absolute_fill(class_name: nil, style: nil, **attributes, &block)
      content = block.call

      tag.div(
        **attributes,
        class: ["animate-it-absolute-fill", class_name].compact,
        style: absolute_fill_style(style)
      ) do
        content
      end
    end

    def render_template(template, assigns: {}, **)
      view_context.render(template:, assigns:, layout: false, **)
    end

    def render_scene_template(name, assigns: {}, **)
      render_template("#{sidecar_template_root}/#{name}", assigns:, **)
    end

    def render_partial(partial, locals: {}, **)
      view_context.render(partial:, locals:, **)
    end

    def motion_asset(path)
      view_context.asset_path(path)
    end

    def motion_image(path, **attributes)
      tag.img(**attributes, src: motion_asset(path))
    end

    def build_factory(name, *traits, **attributes)
      raise AnimateIt::Error, "FactoryBot is not available" unless defined?(FactoryBot)

      FactoryBot.build(name, *traits, **attributes)
    end

    def build_stubbed(name, *traits, **attributes)
      raise AnimateIt::Error, "FactoryBot is not available" unless defined?(FactoryBot)

      FactoryBot.build_stubbed(name, *traits, **attributes)
    end

    # Define singleton methods on `object` from a {name => value} hash.
    # Non-callable values are auto-wrapped in a lambda that ignores its
    # args, so `stub_methods(match, finished_state?: false)` works the
    # same way as `stub_methods(match, finished_state?: -> { false })`.
    # The wrapping lambda accepts `*args` so arity-bearing methods like
    # `user_has_reviewed?(user)` don't raise ArgumentError on the
    # value-shortcut form.
    def stub_methods(object, **stubs)
      stubs.each do |name, value|
        body = value.respond_to?(:call) ? value : ->(*) { value }
        object.define_singleton_method(name) { |*args| body.call(*args) }
      end
      object
    end

    private

    def sidecar_template_root
      context.composition.name.underscore
    end

    def absolute_fill_style(extra_style)
      style(
        "position: absolute",
        "inset: 0",
        "width: 100%",
        "height: 100%",
        "display: flex",
        "flex-direction: column",
        extra_style
      )
    end
  end
end
