# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::RuleResult, type: :service do
  let(:entity) { instance_double(Kyc::CorporateEntity) }

  describe "status helpers" do
    it "met? returns true when status is :met" do
      result = described_class.new(rule_name: "Test", entity: entity, status: :met, requirements: [ "passport" ], satisfied: [ "passport" ], missing: [])
      expect(result).to be_met
      expect(result).not_to be_unmet
    end

    it "unmet? returns true when status is :unmet" do
      result = described_class.new(rule_name: "Test", entity: entity, status: :unmet, requirements: [ "passport" ], satisfied: [], missing: [ "passport" ])
      expect(result).to be_unmet
    end

    it "not_applicable? returns true when status is :not_applicable" do
      result = described_class.new(rule_name: "Test", entity: entity, status: :not_applicable, requirements: [], satisfied: [], missing: [])
      expect(result).to be_not_applicable
    end
  end
end
