# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::RuleRegistry, type: :service do
  before { described_class.reset! }

  describe ".register" do
    it "adds a rule class" do
      stub_const("TestRule", Class.new(Kyc::Compliance::BaseRule))
      # BaseRule.inherited auto-registers, but we reset, so re-register
      described_class.register(TestRule)
      expect(described_class.all).to include(TestRule)
    end

    it "does not add duplicates" do
      stub_const("TestRule", Class.new)
      described_class.register(TestRule)
      described_class.register(TestRule)
      expect(described_class.all.count { |r| r == TestRule }).to eq(1)
    end
  end

  describe ".all" do
    it "returns a copy of the registry" do
      result = described_class.all
      result << "garbage"
      expect(described_class.all).not_to include("garbage")
    end
  end
end
