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

    context "when the document type has no resolvable validity policy (out of rollout)" do
      it "keeps the pre-MH-198 behaviour of counting on status: :complete alone" do
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete,
               document_type: "driving_licence")

        dim = calculator.dimensions.find { |d| d.key == :extraction }
        expect(dim.numerator).to eq(1)
        expect(dim.denominator).to eq(1)
      end
    end

    context "when the document type has a resolvable validity policy (MH-198)" do
      def validity_dates_for(normalized:, confidence: 0.95)
        { "raw" => normalized, "normalized" => normalized, "confidence" => confidence, "provenance" => "ai_extraction" }
      end

      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport", effective_from: Date.new(2020, 1, 1),
          mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
        )
      end

      it "counts a valid document as satisfying extraction completeness" do
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete,
               document_type: "passport",
               validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 2.years).iso8601) })

        dim = calculator.dimensions.find { |d| d.key == :extraction }
        expect(dim.numerator).to eq(1)
        expect(dim.denominator).to eq(1)
      end

      it "counts an expiring_soon document as satisfying extraction completeness" do
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete,
               document_type: "passport",
               validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 10).iso8601) })

        dim = calculator.dimensions.find { |d| d.key == :extraction }
        expect(dim.numerator).to eq(1)
        expect(dim.denominator).to eq(1)
      end

      it "does not count an expired document as satisfying extraction completeness" do
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete,
               document_type: "passport",
               validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date - 1).iso8601) })

        dim = calculator.dimensions.find { |d| d.key == :extraction }
        expect(dim.numerator).to eq(0)
        expect(dim.denominator).to eq(1)
      end

      it "does not count a stale document as satisfying extraction completeness" do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "utility_bill", effective_from: Date.new(2020, 1, 1),
          mode: :freshness, required_dates: [ "issued" ], warning_thresholds: [], max_age_months: 3
        )
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete,
               document_type: "utility_bill",
               validity_dates: { "issued" => validity_dates_for(normalized: (applicant.validity_reference_date - 4.months).iso8601) })

        dim = calculator.dimensions.find { |d| d.key == :extraction }
        expect(dim.numerator).to eq(0)
        expect(dim.denominator).to eq(1)
      end

      it "does not count a confirmation_required document as satisfying extraction completeness" do
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete,
               document_type: "passport",
               validity_dates: { "expiry" => validity_dates_for(normalized: nil, confidence: nil) })

        dim = calculator.dimensions.find { |d| d.key == :extraction }
        expect(dim.numerator).to eq(0)
        expect(dim.denominator).to eq(1)
      end

      it "does not create duplicate assessments across repeated calculator runs" do
        create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete,
               document_type: "passport",
               validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 2.years).iso8601) })

        described_class.for(applicant).dimensions
        expect {
          described_class.for(applicant).dimensions
        }.not_to change(Kyc::DocumentValidityAssessment, :count)
      end
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

  describe "compliance rules dimension" do
    before do
      Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
    end

    it "counts missing Crypto Exchange policy documents in the denominator" do
      applicant.update!(sector: :crypto_exchange)

      dim = calculator.dimensions.find { |dimension| dimension.key == :compliance_rules }

      expect(dim.numerator).to eq(0)
      expect(dim.denominator).to eq(2)
    end

    it "counts uploaded current Crypto Exchange policy documents in the numerator" do
      applicant.update!(sector: :crypto_exchange)
      create(:kyc_document, applicant: applicant, document_type: :vasp_registration)

      dim = calculator.dimensions.find { |dimension| dimension.key == :compliance_rules }

      expect(dim.numerator).to eq(1)
      expect(dim.denominator).to eq(2)
    end

    it "retains an empty compliance dimension for a general applicant without entities" do
      dim = calculator.dimensions.find { |dimension| dimension.key == :compliance_rules }

      expect(dim.numerator).to eq(0)
      expect(dim.denominator).to eq(0)
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
