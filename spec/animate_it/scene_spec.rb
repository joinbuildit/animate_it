require "rails_helper"

RSpec.describe AnimateIt::Scene do
  let(:composition_class) do
    Class.new(AnimateIt::Composition) do
      id "scene-test-#{SecureRandom.hex(4)}"
      fps 30
      size 100, 100
      duration 30.frames
    end
  end

  def fresh_scene_class(&body)
    klass = Class.new(described_class)
    klass.composition_class = composition_class
    klass.class_eval(&body) if body
    # Replace #body so render() doesn't try to call render_scene_template
    # on a non-existent sidecar template.
    klass.define_method(:body) { "" }
    klass
  end

  def scene_at(klass, frame)
    context = composition_class.frame_context(frame:, props: {})
    klass.new(context:, props: context.props)
  end

  describe "#expose" do
    let(:view_context) { Object.new }
    let(:scene) do
      instance = scene_at(fresh_scene_class, 0)
      instance.instance_variable_set(:@view_context, view_context)
      instance
    end

    it "sets keyword args as instance variables on the view context" do
      scene.expose(foo: 1, bar: "two")

      expect(view_context.instance_variable_get(:@foo)).to eq(1)
      expect(view_context.instance_variable_get(:@bar)).to eq("two")
    end

    it "pulls positional keys from `from:` and ignores unlisted keys" do
      fixtures = { job: "the-job", user: "the-user", other: "skip-me" }

      scene.expose(:job, :user, from: fixtures)

      expect(view_context.instance_variable_get(:@job)).to eq("the-job")
      expect(view_context.instance_variable_get(:@user)).to eq("the-user")
      expect(view_context.instance_variable_defined?(:@other)).to be(false)
    end

    it "combines `from:` with explicit keyword overrides" do
      fixtures = { job: "the-job" }

      scene.expose(:job, from: fixtures, top_match: "match-1")

      expect(view_context.instance_variable_get(:@job)).to eq("the-job")
      expect(view_context.instance_variable_get(:@top_match)).to eq("match-1")
    end
  end

  describe ".fixtures" do
    it "memoizes the block result across calls" do
      counter = []
      klass = fresh_scene_class do
        fixtures do
          counter << :build
          { a: 1 }
        end
      end

      5.times { klass.fixtures }

      expect(counter).to eq([:build])
      expect(klass.fixtures).to eq({ a: 1 })
    end

    it "rebuilds after reset_fixtures!" do
      counter = []
      klass = fresh_scene_class do
        fixtures do
          counter << :build
          { a: 1 }
        end
      end

      klass.fixtures
      klass.reset_fixtures!
      klass.fixtures

      expect(counter).to eq(%i[build build])
    end

    it "resets Faker before invoking the block when seed is given" do
      skip "Faker not available in this environment" unless defined?(Faker)

      klass = fresh_scene_class do
        fixtures(seed: 42) { Faker::Name.first_name }
      end

      first = klass.fixtures
      klass.reset_fixtures!
      second = klass.fixtures

      expect(second).to eq(first)
    end

    it "calls FactoryBot.find_definitions when no factories are loaded" do
      skip "FactoryBot not available" unless defined?(FactoryBot)

      allow(FactoryBot).to receive(:factories).and_return([])
      allow(FactoryBot).to receive(:find_definitions)

      klass = fresh_scene_class do
        fixtures { { ok: true } }
      end

      klass.fixtures

      expect(FactoryBot).to have_received(:find_definitions).at_least(:once)
    end
  end

  describe "auto current_frame on render" do
    let(:view_context) { instance_double(ActionView::Base, controller: nil) }

    it "sets the class-level current_frame to the scene's local_frame" do
      klass = fresh_scene_class

      scene_at(klass, 12).render(view_context)

      expect(klass.current_frame).to eq(12)

      scene_at(klass, 27).render(view_context)

      expect(klass.current_frame).to eq(27)
    end

    it "is available to fixture closures via the class accessor" do
      klass = fresh_scene_class
      observed = []
      object = Object.new
      object.define_singleton_method(:frame_phase) { klass.current_frame }

      scene_at(klass, 7).render(view_context)
      observed << object.frame_phase
      scene_at(klass, 21).render(view_context)
      observed << object.frame_phase

      expect(observed).to eq([7, 21])
    end
  end

  describe ".disable_fragment_caching!" do
    let(:controller) { Class.new { attr_accessor :perform_caching }.new }
    let(:view_context) { instance_double(ActionView::Base, controller: controller) }

    it "turns perform_caching off on the controller before body runs" do
      klass = fresh_scene_class do
        disable_fragment_caching!
      end
      controller.perform_caching = true

      scene_at(klass, 0).render(view_context)

      expect(controller.perform_caching).to be(false)
    end

    it "is a no-op when the macro isn't declared" do
      klass = fresh_scene_class
      controller.perform_caching = true

      scene_at(klass, 0).render(view_context)

      expect(controller.perform_caching).to be(true)
    end

    it "doesn't blow up when view_context lacks a controller that responds to perform_caching=" do
      klass = fresh_scene_class do
        disable_fragment_caching!
      end
      bare_view_context = Object.new
      bare_view_context.define_singleton_method(:controller) { Object.new }

      expect { scene_at(klass, 0).render(bare_view_context) }.not_to raise_error
    end
  end
end
