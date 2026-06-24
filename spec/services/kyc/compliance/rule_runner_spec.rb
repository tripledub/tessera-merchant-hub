# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::RuleRunner, type: :service do
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let(:entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :corporate) }

  before do
    Kyc::Compliance::RuleRegistry.reset!

    stub_const("DummyRule", Class.new(Kyc::Compliance::BaseRule) {
      def applies_to?(entity)
        entity.corporate?
      end

      def evaluate(entity)
        build_result(entity: entity, requirements: [ "certificate_of_incorporation" ], satisfied: [])
      end
    })
  end

  describe ".evaluate_entity" do
    it "returns results for all applicable rules" do
      results = described_class.evaluate_entity(entity)
      expect(results.size).to eq(1)
      expect(results.first).to be_unmet
      expect(results.first.missing).to eq([ "certificate_of_incorporation" ])
    end

    it "returns not_applicable for non-matching rules" do
      individual = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual, name: "Jane Doe")
      results = described_class.evaluate_entity(individual)
      expect(results.first).to be_not_applicable
    end
  end

  describe ".evaluate_applicant" do
    it "evaluates all entities for the applicant" do
      entity # ensure created
      create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual, name: "Jane Doe")

      results = described_class.evaluate_applicant(applicant)
      expect(results.size).to eq(2)
    end
  end
end
