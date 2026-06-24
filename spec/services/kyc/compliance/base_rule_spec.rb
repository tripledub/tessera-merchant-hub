# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::BaseRule, type: :service do
  describe ".inherited" do
    it "auto-registers subclasses" do
      Kyc::Compliance::RuleRegistry.reset!
      stub_const("AutoRegisteredRule", Class.new(described_class))
      expect(Kyc::Compliance::RuleRegistry.all).to include(AutoRegisteredRule)
    end
  end

  describe "#applies_to?" do
    it "raises NotImplementedError" do
      rule = described_class.new
      expect { rule.applies_to?(nil) }.to raise_error(NotImplementedError)
    end
  end

  describe "#evaluate" do
    it "raises NotImplementedError" do
      rule = described_class.new
      expect { rule.evaluate(nil) }.to raise_error(NotImplementedError)
    end
  end
end
