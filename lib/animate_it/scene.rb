module AnimateIt
  class Scene
    include AnimationHelpers
    include ViewHelpers
    include TextEffects

    attr_reader :context, :props, :view_context

    def initialize(context:, props:)
      @context = context
      @props = props
    end

    delegate :frame, :local_frame, :fps, :progress, :interpolate, :spring, to: :context

    # ----- class-level DSL -----------------------------------------------
    class << self
      # Sidecar template name. Defaults to "canvas" — i.e. a scene whose
      # composition is `MyHero` looks for `app/videos/my_hero/canvas.html.*`.
      # The sidecar may be authored in HAML (`canvas.html.haml`) or ERB
      # (`canvas.html.erb`); Rails resolves whichever exists. Override to point
      # to a sibling template instead.
      def template(name = nil)
        @template = name.to_s if name
        @template ||= "canvas"
      end

      # Outer wrapper class for the scene's content. Defaults to
      # "hero-render-canvas" (the convention used by all current heros).
      def canvas_class(value = nil)
        @canvas_class = value.to_s if value
        @canvas_class ||= "hero-render-canvas"
      end

      # Declare an animatable element by name. Animation properties are
      # attached via the block:
      #
      #   animate :step_1 do
      #     fade  during: 10..30
      #     slide during: 10..30, from: 16
      #   end
      #
      # The framework auto-generates the `[data-anim="step_1"]` CSS rules
      # and the per-frame CSS variables — no `:css` block in the HAML.
      def animate(name, &block)
        animations.add(name, block)
      end

      def animations
        @animations ||= AnimationSet.new
      end

      # Register pure per-frame CSS-variable math for client recording.
      def track_vars(name = :root, &block)
        raise ArgumentError, "track_vars requires a block" unless block

        own_var_groups[name.to_sym] = block
      end

      def var_groups
        inherited = superclass.respond_to?(:var_groups) ? superclass.var_groups : {}
        inherited.merge(own_var_groups)
      end

      def text_track(key, &block)
        raise ArgumentError, "text_track requires a block" unless block

        own_text_tracks[key.to_sym] = block
      end

      def text_tracks
        inherited = superclass.respond_to?(:text_tracks) ? superclass.text_tracks : {}
        inherited.merge(own_text_tracks)
      end

      # Composition class this scene belongs to. Set by the engine when the
      # scene is mounted via `composition.scene MyScene` / single-scene
      # auto-mount; lets animation property procs reach `Composition.beats`.
      attr_accessor :composition_class

      # Set automatically at the start of every `render` to the scene's
      # current local_frame. Fixture closures (e.g. a singleton-method
      # stub that needs to vary by frame) can call `MyScene.current_frame`
      # without the scene having to remember to assign it in `body`.
      attr_accessor :current_frame

      # Declare a class-level fixture builder. With a block, registers the
      # builder *lazily* (no work done at class load). Without a block,
      # invokes the registered builder once behind a mutex — `Faker::Config.random`
      # is reset to `Random.new(seed)` first (when `seed:` was given) and
      # `FactoryBot.find_definitions` is invoked if no factories are loaded.
      # Subsequent calls return the memoized hash.
      #
      #   class HeroScene < AnimateIt::Scene
      #     fixtures(seed: 42) do
      #       company = build_stubbed_company
      #       { company:, job: build_stubbed_job(company) }
      #     end
      #   end
      #
      #   HeroScene.fixtures  # → builds once, returns hash
      def fixtures(seed: nil, &block)
        if block
          @fixtures_block = block
          @fixtures_seed = seed
          return nil
        end

        return @fixtures_value if defined?(@fixtures_value) && @fixtures_value

        @fixtures_mutex ||= Mutex.new
        @fixtures_mutex.synchronize do
          next @fixtures_value if @fixtures_value

          FactoryBot.find_definitions if defined?(FactoryBot) && FactoryBot.factories.none?
          Faker::Config.random = Random.new(@fixtures_seed) if defined?(Faker) && @fixtures_seed
          @fixtures_value = @fixtures_block&.call
        end
      end

      def reset_fixtures!
        return unless @fixtures_mutex

        @fixtures_mutex.synchronize { @fixtures_value = nil }
      end

      # Toggles fragment caching off for the rendering controller before
      # `body` runs. Defeats the dev-environment `cache do ... end` blocks
      # in production partials that key on stable record `updated_at`s and
      # would otherwise reuse frame 1's HTML for every subsequent frame.
      def disable_fragment_caching!
        @disable_fragment_caching = true
      end

      def fragment_caching_disabled?
        @disable_fragment_caching == true
      end

      def own_var_groups
        @own_var_groups ||= {}
      end

      def own_text_tracks
        @own_text_tracks ||= {}
      end

      # Class-side mirror of ViewHelpers#stub_methods so class-method
      # fixture builders (which run before any Scene instance exists)
      # can also use the helper to define singleton-method stubs on
      # build_stubbed records.
      def stub_methods(object, **stubs)
        stubs.each do |name, value|
          body = value.respond_to?(:call) ? value : ->(*) { value }
          object.define_singleton_method(name) { |*args| body.call(*args) }
        end
        object
      end
    end

    # ----- runtime --------------------------------------------------------

    # Stash view_context so helpers (`tag`, `safe_join`, `capture`) work,
    # then call `body` for the actual markup. Subclasses should override
    # `body` (no args) — view_context is already available via the
    # accessor.
    #
    # The framework's filmstrip + frame controllers call `render(view_context)`;
    # don't override that signature unless you really need to.
    def render(view_context)
      @view_context = view_context
      self.class.current_frame = local_frame
      if self.class.fragment_caching_disabled? &&
         view_context.respond_to?(:controller) &&
         view_context.controller.respond_to?(:perform_caching=)
        view_context.controller.perform_caching = false
      end
      body
    end

    # Set ivars on the view_context so templates rendered via
    # `render_scene_template` / `view_context.render(template:)` can read
    # them as `@foo`. ActionView's `assigns:` keyword doesn't propagate
    # through template-level renders, so we push ivars directly onto the
    # same view context the template will be evaluated against.
    #
    #   expose(:job, :user, from: fixtures, top_match: matches.first)
    #
    # The positional `keys` are pulled from the `from:` hash by name; the
    # keyword args are set verbatim.
    def expose(*keys, from: nil, **ivars)
      keys.each { |k| view_context.instance_variable_set("@#{k}", from[k]) } if from
      ivars.each { |k, v| view_context.instance_variable_set("@#{k}", v) }
    end

    # Default markup: canvas wrapper + sidecar template + auto-generated
    # animation CSS. Override in a subclass when the composition is
    # programmatic (no sidecar template) or has multiple acts.
    def body
      tag.div(class: self.class.canvas_class, style: canvas_style) do
        absolute_fill(style: animation_var_style, **animate_wrapper_attributes) do
          parts = []
          parts << generated_animation_styles if self.class.animations.elements.any?
          parts << render_scene_template(self.class.template)
          view_context.safe_join(parts)
        end
      end
    end

    # Convenience: when a subclass overrides `render` it can call this to
    # get the same wrapper + animation-var div around custom content.
    def with_canvas(&block)
      tag.div(class: self.class.canvas_class, style: canvas_style) do
        absolute_fill(style: animation_var_style, **animate_wrapper_attributes) do
          parts = []
          parts << generated_animation_styles if self.class.animations.elements.any?
          parts << view_context.capture(&block) if block
          view_context.safe_join(parts)
        end
      end
    end

    # CSS var bag computed from this frame's animations. Available inside
    # custom render methods that want extra inline styles.
    def animation_vars(group = nil, **extras)
      return Style.vars(**evaluate_var_group(group), **extras) if group

      Style.vars(**self.class.animations.vars_for(self), **extras)
    end

    def evaluate_var_group(name)
      block = self.class.var_groups[name.to_sym]
      raise Error, "Unknown track_vars group :#{name} on #{self.class}" unless block

      instance_exec(&block)
    end

    def evaluate_text_track(key)
      block = self.class.text_tracks[key.to_sym]
      raise Error, "Unknown text_track :#{key} on #{self.class}" unless block

      instance_exec(&block)
    end

    delegate :composition_class, to: :class

    private

    def tag
      view_context.tag
    end

    def safe_join(...)
      view_context.safe_join(...)
    end

    def capture(...)
      view_context.capture(...)
    end

    def animate_wrapper_attributes
      return {} unless self.class.animations.elements.any?

      { data: { animate_vars: Tracks::Recorder::ANIMATE_GROUP } }
    end

    def generated_animation_styles
      view_context.tag.style(self.class.animations.css_rules.html_safe)
    end

    def canvas_style
      Style.build(
        "position: relative",
        "width: 100%",
        "height: 100%",
        "display: flex",
        "align-items: center",
        "justify-content: center",
        "padding: 40px 80px",
        "box-sizing: border-box",
        "font-family: League Spartan, Arial, Helvetica, sans-serif",
        "background: transparent"
      )
    end

    def animation_var_style
      Style.build(
        "align-items: center",
        "justify-content: center",
        animation_vars
      )
    end
  end
end
