# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::ReadinessAssessment, type: :service do
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let(:entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :corporate) }

  before do
    Kyc::Compliance::RuleRegistry.reset!

    stub_const("MetRule", Class.new(Kyc::Compliance::BaseRule) {
      def applies_to?(_entity)
        true
      end

      def evaluate(entity)
        build_result(
          entity: entity,
          requirements: [ "certificate_of_incorporation" ],
          satisfied: [ "certificate_of_incorporation" ]
        )
      end
    })
  end

  describe ".for" do
    it "returns an assessment instance" do
      entity # ensure created
      assessment = described_class.for(applicant)
      expect(assessment).to be_a(described_class)
    end
  end

  describe "#compliant?" do
    it "returns true when all rules are met" do
      entity # ensure created
      assessment = described_class.for(applicant)
      expect(assessment).to be_compliant
    end

    it "returns false when any rule is unmet" do
      Kyc::Compliance::RuleRegistry.reset!

      stub_const("UnmetRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "certificate_of_incorporation" ],
            satisfied: []
          )
        end
      })

      entity # ensure created
      assessment = described_class.for(applicant)
      expect(assessment).not_to be_compliant
    end

    it "returns false when an applicant-level blocking document requirement is unmet" do
      applicant.update!(sector: :crypto_exchange)

      assessment = described_class.for(applicant)

      expect(assessment.entity_count).to eq(0)
      expect(assessment.policy_results.size).to eq(2)
      expect(assessment).not_to be_compliant
    end

    it "returns true when applicant-level document requirements are met and there are no entities" do
      applicant.update!(sector: :crypto_exchange)
      create(:kyc_document, applicant: applicant, document_type: :vasp_registration)
      create(:kyc_document, applicant: applicant, document_type: :wallet_custody_infrastructure_attestation)

      assessment = described_class.for(applicant)

      expect(assessment.entity_count).to eq(0)
      expect(assessment).to be_compliant
    end
  end

  describe "#all_results" do
    it "includes policy and entity results while preserving entity count semantics" do
      applicant.update!(sector: :crypto_exchange)
      entity

      assessment = described_class.for(applicant.reload)

      expect(assessment.entity_count).to eq(1)
      expect(assessment.policy_results.size).to eq(2)
      expect(assessment.all_results).to contain_exactly(*assessment.policy_results, *assessment.results_for(entity))
      expect(assessment.result_count).to eq(3)
    end
  end

  describe "#compliant_entity_count" do
    it "counts entities where all rules are met" do
      entity # ensure created
      create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual, name: "Test Person")
      assessment = described_class.for(applicant.reload)
      expect(assessment.compliant_entity_count).to eq(2)
    end
  end

  describe "#results_for" do
    it "returns results for a specific entity" do
      entity # ensure created
      assessment = described_class.for(applicant)
      results = assessment.results_for(entity)
      expect(results).not_to be_empty
      expect(results.first.entity).to eq(entity)
    end

    it "returns empty array for unknown entity" do
      entity # ensure created
      other = create(:kyc_corporate_entity, applicant: create(:applicant), kyc_document: document, entity_type: :corporate, name: "Other Corp")
      assessment = described_class.for(applicant)
      expect(assessment.results_for(other)).to eq([])
    end
  end

  describe "#unmet_results" do
    it "returns only unmet results" do
      Kyc::Compliance::RuleRegistry.reset!

      stub_const("MixedRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "certificate_of_incorporation", "articles_of_association" ],
            satisfied: [ "certificate_of_incorporation" ]
          )
        end
      })

      entity # ensure created
      assessment = described_class.for(applicant)
      expect(assessment.unmet_results).to all(be_unmet)
      expect(assessment.unmet_results.size).to eq(1)
    end
  end

  describe "#confirmation_required_results (MH-198)" do
    it "is distinct from unmet_results and blocks compliant?" do
      Kyc::Compliance::RuleRegistry.reset!

      stub_const("AwaitingRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "passport" ],
            satisfied: [],
            awaiting_confirmation: [ "passport" ]
          )
        end
      })

      entity # ensure created
      assessment = described_class.for(applicant)

      expect(assessment.confirmation_required_results.size).to eq(1)
      expect(assessment.unmet_results).to be_empty
      expect(assessment).not_to be_compliant
    end
  end
end
