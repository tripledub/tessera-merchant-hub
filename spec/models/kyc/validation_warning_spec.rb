# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::ValidationWarning, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:applicant) }
    it { is_expected.to belong_to(:kyc_document) }
    it { is_expected.to belong_to(:corporate_entity).class_name("Kyc::CorporateEntity").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:warning_type) }
    it { is_expected.to validate_presence_of(:message) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:warning_type).with_values(percentage_deviation: 0, nominee_detected: 1) }
  end

  describe "#typed_metadata" do
    let(:applicant) { create(:applicant) }
    let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
    let(:entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document) }

    context "when percentage_deviation" do
      it "returns a PercentageDeviation StoreModel" do
        warning = described_class.create!(
          applicant: applicant,
          kyc_document: document,
          corporate_entity: entity,
          warning_type: :percentage_deviation,
          message: "Ownership sums to 98.16%",
          metadata: { expected: 100.0, actual: 98.16, deviation: 1.84 }
        )

        warning.reload
        typed = warning.typed_metadata
        expect(typed).to be_a(Kyc::ValidationWarningMetadata::PercentageDeviation)
        expect(typed.expected).to eq(100.0)
        expect(typed.actual).to eq(98.16)
        expect(typed.deviation).to eq(1.84)
      end
    end

    context "when nominee_detected" do
      it "returns a NomineeDetected StoreModel" do
        warning = described_class.create!(
          applicant: applicant,
          kyc_document: document,
          corporate_entity: entity,
          warning_type: :nominee_detected,
          message: "Nominee detected: Acme Corp",
          metadata: { detection_reason: "nominee_jurisdiction", jurisdiction: "CY" }
        )

        warning.reload
        typed = warning.typed_metadata
        expect(typed).to be_a(Kyc::ValidationWarningMetadata::NomineeDetected)
        expect(typed.detection_reason).to eq("nominee_jurisdiction")
        expect(typed.jurisdiction).to eq("CY")
      end
    end
  end

  describe "acknowledged" do
    let(:warning) { create(:kyc_validation_warning) }

    it "defaults to false" do
      expect(warning.acknowledged).to be false
    end
  end
end
