# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::CompletenessCalculator, type: :service do
  subject(:calculator) { described_class.for(applicant) }

  let(:applicant) { create(:applicant) }


  describe "#overall_percentage" do
    context "with no data" do
      it "returns 0.0" do
        expect(calculator.overall_percentage).to eq(0.0)
      end
    end

    context "with only some dimensions populated" do
      it "redistributes weight among active dimensions" do
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)

        result = calculator.overall_percentage
        expect(result).to eq(100.0)
      end
    end

    context "with mixed completion across active dimensions" do
      it "calculates weighted average of active dimensions only" do
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)
        create(:kyc_document, applicant: applicant, classification_status: :unclassified)
        create(:kyc_principal, applicant: applicant)

        result = calculator.overall_percentage
        expect(result).to be_between(0.1, 99.9)
      end
    end
  end

  describe "#dimensions" do
    it "returns five dimensions" do
      expect(calculator.dimensions.size).to eq(5)
      expect(calculator.dimensions.map(&:key)).to eq(
        %i[classification extraction identity_verification compliance_rules ownership_resolution]
      )
    end
  end

  describe "classification dimension" do
    it "calculates confirmed / total documents" do
      create(:kyc_document, applicant: applicant, classification_status: :confirmed)
      create(:kyc_document, applicant: applicant, classification_status: :unclassified)
      create(:kyc_document, applicant: applicant, classification_status: :ai_suggested)

      dim = calculator.dimensions.find { |d| d.key == :classification }
      expect(dim.numerator).to eq(1)
      expect(dim.denominator).to eq(3)
      expect(dim.percentage).to eq(33.3)
    end
  end

  describe "extraction dimension" do
    it "calculates extracted / confirmed documents" do
      create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)
      create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
      create(:kyc_document, applicant: applicant, classification_status: :unclassified, status: :complete)

      dim = calculator.dimensions.find { |d| d.key == :extraction }
      expect(dim.numerator).to eq(1)
      expect(dim.denominator).to eq(2)
      expect(dim.percentage).to eq(50.0)
    end
  end

  describe "identity verification dimension" do
    it "calculates principals with identity document / total principals" do
      p1 = create(:kyc_principal, applicant: applicant)
      _p2 = create(:kyc_principal, applicant: applicant)
      create(:kyc_document, applicant: applicant, kyc_principal: p1, document_type: :passport)

      dim = calculator.dimensions.find { |d| d.key == :identity_verification }
      expect(dim.numerator).to eq(1)
      expect(dim.denominator).to eq(2)
      expect(dim.percentage).to eq(50.0)
    end

    it "counts driving licence as valid identity" do
      p1 = create(:kyc_principal, applicant: applicant)
      create(:kyc_document, applicant: applicant, kyc_principal: p1, document_type: :driving_licence)

      dim = calculator.dimensions.find { |d| d.key == :identity_verification }
      expect(dim.numerator).to eq(1)
      expect(dim.denominator).to eq(1)
    end
  end

  describe "ownership resolution dimension" do
    let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }

    it "calculates entities without unresolved_chain warnings / total" do
      e1 = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document)
      e2 = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document)
      create(:kyc_validation_warning, applicant: applicant, corporate_entity: e2,
             warning_type: :unresolved_chain, message: "Unresolved")

      dim = calculator.dimensions.find { |d| d.key == :ownership_resolution }
      expect(dim.numerator).to eq(1)
      expect(dim.denominator).to eq(2)
      expect(dim.percentage).to eq(50.0)
    end
  end

  describe "#as_chart_json" do
    it "returns overall and dimensions" do
      json = calculator.as_chart_json
      expect(json).to have_key(:overall)
      expect(json).to have_key(:dimensions)
      expect(json[:dimensions].size).to eq(5)
      expect(json[:dimensions].first).to include(:key, :label, :percentage, :numerator, :denominator)
    end
  end
end
