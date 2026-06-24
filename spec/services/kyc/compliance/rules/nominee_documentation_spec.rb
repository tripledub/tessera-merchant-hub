# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::Rules::NomineeDocumentation, type: :service do
  subject(:rule) { described_class.new }

  let(:applicant) { create(:applicant) }
  let(:source_document) { create(:kyc_document, applicant: applicant) }

  describe "#evaluate" do
    context "when the entity has a nominee_detected warning and declaration_of_trust linked" do
      it "returns :met" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :corporate, name: "Northwind Holdings Ltd")
        create(:kyc_validation_warning, applicant: applicant, kyc_document: source_document,
                                        corporate_entity: entity, warning_type: :nominee_detected)
        create(:kyc_document, applicant: applicant, corporate_entity: entity,
                              document_type: :declaration_of_trust)

        result = rule.evaluate(entity)

        expect(result).to be_met
        expect(result.satisfied).to contain_exactly("declaration_of_trust")
        expect(result.missing).to be_empty
      end
    end

    context "when the entity has a nominee_detected warning but no declaration_of_trust" do
      it "returns :unmet with missing declaration_of_trust" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :corporate, name: "Northwind Holdings Ltd")
        create(:kyc_validation_warning, applicant: applicant, kyc_document: source_document,
                                        corporate_entity: entity, warning_type: :nominee_detected)

        result = rule.evaluate(entity)

        expect(result).to be_unmet
        expect(result.missing).to contain_exactly("declaration_of_trust")
      end
    end

    context "when the entity has no nominee_detected warning" do
      it "returns :not_applicable for a corporate entity" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :corporate, name: "Northwind Holdings Ltd")

        result = rule.evaluate(entity)

        expect(result).to be_not_applicable
      end

      it "returns :not_applicable for an individual entity" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :individual, name: "Alex Thompson")

        result = rule.evaluate(entity)

        expect(result).to be_not_applicable
      end
    end
  end
end
