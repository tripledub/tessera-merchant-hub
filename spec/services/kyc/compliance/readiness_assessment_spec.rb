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

    it "returns false when applicant-level document requirements are met but no ownership is captured (MH-251)" do
      applicant.update!(sector: :crypto_exchange)
      create(:kyc_document, applicant: applicant, document_type: :vasp_registration)
      create(:kyc_document, applicant: applicant, document_type: :wallet_custody_infrastructure_attestation)

      assessment = described_class.for(applicant)

      expect(assessment.entity_count).to eq(0)
      expect(assessment).not_to be_compliant
      expect(assessment.outcome).to eq(:not_assessable)
    end

    it "returns true when those requirements are met and staff attested there are no corporate owners" do
      applicant.update!(sector: :crypto_exchange)
      applicant.attest_no_corporate_owners!(by: create(:user))
      create(:kyc_document, applicant: applicant, document_type: :vasp_registration)
      create(:kyc_document, applicant: applicant, document_type: :wallet_custody_infrastructure_attestation)

      assessment = described_class.for(applicant.reload)

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

  # MH-251: readiness is a four-state outcome. Precedence is
  # non_compliant > not_assessable > requires_review > compliant.
  describe "#outcome (MH-251)" do
    def unmet_rule!
      Kyc::Compliance::RuleRegistry.reset!
      stub_const("UnmetRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity) = true

        def evaluate(entity)
          build_result(entity: entity, requirements: [ "certificate_of_incorporation" ], satisfied: [])
        end
      })
    end

    def awaiting_rule!
      Kyc::Compliance::RuleRegistry.reset!
      stub_const("AwaitingRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity) = true

        def evaluate(entity)
          build_result(entity: entity, requirements: [ "passport" ], satisfied: [], awaiting_confirmation: [ "passport" ])
        end
      })
    end

    def warning!(type, **attrs)
      create(:kyc_validation_warning, applicant: applicant, kyc_document: nil, corporate_entity: nil,
                                      warning_type: type, **attrs)
    end

    it "is :compliant when entities exist and every rule is met" do
      entity

      expect(described_class.for(applicant).outcome).to eq(:compliant)
    end

    it "is :not_assessable when no ownership entities are captured and nobody has attested" do
      assessment = described_class.for(applicant)

      expect(assessment.result_count).to eq(0)
      expect(assessment.outcome).to eq(:not_assessable)
      expect(assessment).not_to be_compliant
    end

    it "is :compliant for an empty ownership graph once staff attested no corporate owners" do
      applicant.attest_no_corporate_owners!(by: create(:user))

      expect(described_class.for(applicant.reload).outcome).to eq(:compliant)
    end

    it "ignores the attestation once ownership entities exist" do
      applicant.attest_no_corporate_owners!(by: create(:user))
      unmet_rule!
      entity

      expect(described_class.for(applicant.reload).outcome).to eq(:non_compliant)
    end

    it "is :non_compliant when a blocking rule is unmet" do
      unmet_rule!
      entity

      expect(described_class.for(applicant).outcome).to eq(:non_compliant)
    end

    it "is :non_compliant rather than :not_assessable when a blocking document requirement is unmet" do
      applicant.update!(sector: :crypto_exchange)

      expect(described_class.for(applicant).outcome).to eq(:non_compliant)
    end

    it "is :requires_review when only confirmation is outstanding" do
      awaiting_rule!
      entity

      expect(described_class.for(applicant).outcome).to eq(:requires_review)
    end

    it "is :requires_review when an unresolved ownership chain warning is open" do
      entity
      warning!(:unresolved_chain, message: "Unresolved ownership chain: Test Corp")

      expect(described_class.for(applicant).outcome).to eq(:requires_review)
    end

    it "does not hold readiness back for an acknowledged unresolved chain warning" do
      entity
      warning!(:unresolved_chain, message: "Unresolved ownership chain: Test Corp", acknowledged: true)

      expect(described_class.for(applicant).outcome).to eq(:compliant)
    end

    it "is :non_compliant when a UBO above threshold is not captured as an ownership entity, even if attested" do
      applicant.attest_no_corporate_owners!(by: create(:user))
      warning!(:ubo_threshold_exceeded, message: "UBO identified", metadata: { individual_name: "Test Person" })

      assessment = described_class.for(applicant.reload)

      expect(assessment.outcome).to eq(:non_compliant)
      expect(assessment.unmet_results.map(&:missing).flatten).to include("ownership_entity")
    end

    it "no longer flags the UBO once a matching ownership entity is captured" do
      create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual, name: "Test Person")
      warning!(:ubo_threshold_exceeded, message: "UBO identified", metadata: { individual_name: "test person " })

      expect(described_class.for(applicant).outcome).to eq(:compliant)
    end

    it "prefers :non_compliant over :requires_review" do
      unmet_rule!
      entity
      warning!(:unresolved_chain, message: "Unresolved ownership chain: Test Corp")

      expect(described_class.for(applicant).outcome).to eq(:non_compliant)
    end
  end
end
