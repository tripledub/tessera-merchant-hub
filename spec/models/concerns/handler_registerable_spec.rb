# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandlerRegisterable do
  let(:registry) do
    Module.new { extend HandlerRegisterable }
  end

  let(:matching_handler) do
    Class.new do
      def self.handles?(condition)
        condition[:type] == :match
      end

      attr_reader :condition

      def initialize(condition)
        @condition = condition
      end
    end
  end

  let(:non_matching_handler) do
    Class.new do
      def self.handles?(_condition)
        false
      end
    end
  end

  let(:default_handler) do
    Class.new do
      def self.handles?(_condition)
        true
      end

      attr_reader :condition

      def initialize(condition)
        @condition = condition
      end
    end
  end

  describe "#registered_handlers" do
    it "returns an empty hash by default" do
      expect(registry.registered_handlers).to eq({})
    end

    it "persists registered handlers" do
      registry.registered_handlers[:test] = matching_handler
      expect(registry.registered_handlers[:test]).to eq(matching_handler)
    end
  end

  describe "#obtain" do
    it "returns an instance of the first matching handler" do
      registry.registered_handlers[:matcher] = matching_handler
      result = registry.obtain({ type: :match })
      expect(result).to be_a(matching_handler)
      expect(result.condition).to eq({ type: :match })
    end

    it "skips non-matching handlers" do
      registry.registered_handlers[:nope] = non_matching_handler
      registry.registered_handlers[:yep] = matching_handler
      result = registry.obtain({ type: :match })
      expect(result).to be_a(matching_handler)
    end

    it "raises NoHandlerAccepted when no handler matches and no default" do
      registry.registered_handlers[:nope] = non_matching_handler
      expect { registry.obtain({ type: :unknown }) }
        .to raise_error(HandlerRegisterable::NoHandlerAccepted)
    end

    it "falls back to default handler when no registered handler matches" do
      registry.registered_handlers[:nope] = non_matching_handler
      registry.default = default_handler
      result = registry.obtain({ type: :unknown })
      expect(result).to be_a(default_handler)
      expect(result.condition).to eq({ type: :unknown })
    end

    it "prioritises later-registered handlers over earlier ones" do
      early_handler = Class.new do
        def self.handles?(_condition) = true
        attr_reader :condition
        def initialize(condition) = @condition = condition
      end

      late_handler = Class.new do
        def self.handles?(_condition) = true
        attr_reader :condition
        def initialize(condition) = @condition = condition
      end

      registry.registered_handlers[:early] = early_handler
      registry.registered_handlers[:late] = late_handler

      result = registry.obtain({ type: :any })
      expect(result).to be_a(late_handler)
    end
  end
end
