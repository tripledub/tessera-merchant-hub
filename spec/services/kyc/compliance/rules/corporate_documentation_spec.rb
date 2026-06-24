# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::Rules::CorporateDocumentation, type: :service do
  subject(:rule) { described_class.new }

  let(:applicant) { create(:applicant) }
  let(:source_document) { create(:kyc_document, applicant: applicant) }

  describe "#evaluate" do
    context "when corporate entity has certificate_of_incorporation linked" do
      it "returns :met" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :corporate, name: "Northwind Holdings Ltd")
        create(:kyc_document, applicant: applicant, corporate_entity: entity,
                              document_type: :certificate_of_incorporation)

        result = rule.evaluate(entity)

        expect(result).to be_met
        expect(result.satisfied).to contain_exactly("certificate_of_incorporation")
        expect(result.missing).to be_empty
      end
    end

    context "when corporate entity has no certificate_of_incorporation" do
      it "returns :unmet with missing certificate_of_incorporation" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :corporate, name: "Northwind Holdings Ltd")

        result = rule.evaluate(entity)

        expect(result).to be_unmet
        expect(result.missing).to contain_exactly("certificate_of_incorporation")
      end
    end

    context "when entity is an individual" do
      it "returns :not_applicable" do
        entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                                entity_type: :individual, name: "Alex Thompson")

        result = rule.evaluate(entity)

        expect(result).to be_not_applicable
      end
    end
  end
end
