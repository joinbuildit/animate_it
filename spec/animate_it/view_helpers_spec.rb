require "rails_helper"

RSpec.describe AnimateIt::ViewHelpers do
  let(:host_class) { Class.new { include AnimateIt::ViewHelpers } }
  let(:host) { host_class.new }

  describe "#stub_methods" do
    let(:target) { Object.new }

    it "wires lambda values as singleton methods" do
      host.stub_methods(target, foo: -> { :lazy })

      expect(target.foo).to eq(:lazy)
    end

    it "auto-wraps non-callable values in a lambda that returns them" do
      host.stub_methods(target, finished?: false, count: 0, tag: "x")

      expect(target.finished?).to be(false)
      expect(target.count).to eq(0)
      expect(target.tag).to eq("x")
    end

    it "passes positional args through to lambda values" do
      host.stub_methods(target, doubled: ->(n) { n * 2 })

      expect(target.doubled(7)).to eq(14)
    end

    it "ignores positional args on auto-wrapped values" do
      host.stub_methods(target, user_has_reviewed?: true)

      expect(target.user_has_reviewed?(:any_user)).to be(true)
      expect(target.user_has_reviewed?).to be(true)
    end

    it "returns the object so calls can chain" do
      result = host.stub_methods(target, x: 1)

      expect(result).to be(target)
    end

    it "wires multiple stubs in a single call" do
      host.stub_methods(target, a: 1, b: 2, c: -> { 3 })

      expect([target.a, target.b, target.c]).to eq([1, 2, 3])
    end
  end

  describe "#build_stubbed" do
    # A plain (non-ActiveRecord) class + factory keeps the gem's own suite
    # self-contained; the helper under test just delegates to FactoryBot.
    before(:all) do
      stub_widget = Class.new do
        attr_accessor :id, :label
      end
      Object.const_set(:AnimateItStubWidget, stub_widget) unless Object.const_defined?(:AnimateItStubWidget)

      unless FactoryBot::Internal.factories.registered?(:animate_it_stub_widget)
        FactoryBot.define do
          factory :animate_it_stub_widget, class: "AnimateItStubWidget" do
            label { "widget" }
          end
        end
      end
    end

    after(:all) do
      Object.send(:remove_const, :AnimateItStubWidget) if Object.const_defined?(:AnimateItStubWidget)
    end

    it "delegates to FactoryBot.build_stubbed" do
      widget = host.build_stubbed(:animate_it_stub_widget)

      expect(widget).to be_a(AnimateItStubWidget)
      expect(widget.persisted?).to be(true) # build_stubbed assigns an id
      expect(widget.id).to be_present
    end

    it "forwards traits and attributes" do
      widget = host.build_stubbed(:animate_it_stub_widget, label: "custom")

      expect(widget.label).to eq("custom")
    end

    it "raises AnimateIt::Error when FactoryBot is unavailable" do
      hide_const("FactoryBot")

      expect do
        host.build_stubbed(:animate_it_stub_widget)
      end.to raise_error(AnimateIt::Error, /FactoryBot is not available/)
    end
  end
end
