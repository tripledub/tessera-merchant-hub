# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::Rules::UboDocumentRequirements, type: :service do
  subject(:rule) { described_class.new }

  let(:applicant) { create(:applicant) }
  let(:source_document) { create(:kyc_document, applicant: applicant) }

  describe "#applies_to?" do
    it "returns true for an individual with a UBO threshold warning" do
      entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                              entity_type: :individual, name: "Jan Kowalski")
      create(:kyc_validation_warning, applicant: applicant, kyc_document: source_document,
                                      corporate_entity: entity, warning_type: :ubo_threshold_exceeded)

      expect(rule.applies_to?(entity)).to be true
    end

    it "returns false for an individual without a UBO threshold warning" do
      entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                              entity_type: :individual, name: "Jan Kowalski")

      expect(rule.applies_to?(entity)).to be false
    end

    it "returns false for a corporate entity" do
      entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                              entity_type: :corporate, name: "Acme Holdings Ltd")

      expect(rule.applies_to?(entity)).to be false
    end
  end

  describe "#evaluate" do
    context "when the entity is not applicable" do
      it "returns :not_applicable for a corporate entity" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :corporate)

        result = rule.evaluate(entity)

        expect(result).to be_not_applicable
      end

      it "returns :not_applicable for an individual without UBO warning" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :individual, name: "Jan Kowalski")

        result = rule.evaluate(entity)

        expect(result).to be_not_applicable
      end
    end

    context "when the individual is a UBO with no matched principal" do
      let(:entity) do
        create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                      entity_type: :individual, name: "Jan Kowalski")
      end
      let!(:ubo_warning) do
        create(:kyc_validation_warning, applicant: applicant, kyc_document: source_document,
                                        corporate_entity: entity, warning_type: :ubo_threshold_exceeded)
      end

      it "returns :unmet with all requirements missing" do
        create(:kyc_principal, applicant: applicant, name: "Someone Else")

        result = rule.evaluate(entity)

        expect(result).to be_unmet
        expect(result.missing).to contain_exactly("identity", "proof_of_address")
      end
    end

    context "when the individual is a UBO with a matched principal" do
      let(:entity) do
        create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                      entity_type: :individual, name: "Jan Kowalski")
      end
      let!(:ubo_warning) do
        create(:kyc_validation_warning, applicant: applicant, kyc_document: source_document,
                                        corporate_entity: entity, warning_type: :ubo_threshold_exceeded)
      end
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Jan Kowalski") }

      it "returns :unmet when the principal has no documents" do
        result = rule.evaluate(entity)

        expect(result).to be_unmet
        expect(result.missing).to contain_exactly("identity", "proof_of_address")
      end

      it "returns :unmet when only identity document is present" do
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)

        result = rule.evaluate(entity)

        expect(result).to be_unmet
        expect(result.missing).to contain_exactly("proof_of_address")
        expect(result.satisfied).to contain_exactly("identity")
      end

      it "returns :met when passport and utility bill are present" do
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :utility_bill)

        result = rule.evaluate(entity)

        expect(result).to be_met
        expect(result.satisfied).to contain_exactly("identity", "proof_of_address")
        expect(result.missing).to be_empty
      end

      it "accepts driving licence as an alternative identity document" do
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :driving_licence)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :utility_bill)

        result = rule.evaluate(entity)

        expect(result).to be_met
      end

      it "matches principal name case-insensitively" do
        principal.update!(name: "JAN KOWALSKI")

        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :utility_bill)

        result = rule.evaluate(entity)

        expect(result).to be_met
      end
    end
  end
end
