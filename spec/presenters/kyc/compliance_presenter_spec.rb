# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::CompliancePresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant) }
  let(:presenter) { described_class.new(applicant, template) }

  describe "#has_warnings?" do
    it "returns false when no warnings exist" do
      expect(presenter.has_warnings?).to be false
    end

    it "returns true when warnings exist" do
      create(:kyc_validation_warning, applicant: applicant, kyc_document: document)
      expect(presenter.has_warnings?).to be true
    end
  end

  describe "#unacknowledged_count" do
    it "counts only unacknowledged warnings" do
      create(:kyc_validation_warning, applicant: applicant, kyc_document: document, acknowledged: false)
      create(:kyc_validation_warning, applicant: applicant, kyc_document: document, acknowledged: true)
      expect(presenter.unacknowledged_count).to eq(1)
    end
  end

  describe "#count_by_type" do
    it "counts warnings of the given type" do
      create(:kyc_validation_warning, applicant: applicant, kyc_document: document, warning_type: :percentage_deviation)
      create(:kyc_validation_warning, applicant: applicant, kyc_document: document, warning_type: :nominee_detected,
             message: "Nominee detected", metadata: { detection_reason: "keyword_match" })
      expect(presenter.count_by_type(:percentage_deviation)).to eq(1)
      expect(presenter.count_by_type(:nominee_detected)).to eq(1)
      expect(presenter.count_by_type(:unresolved_chain)).to eq(0)
    end
  end

  describe "#warning_type_badge" do
    it "returns amber badge for percentage_deviation" do
      warning = build(:kyc_validation_warning, warning_type: :percentage_deviation)
      html = presenter.warning_type_badge(warning)
      expect(html).to include("% Deviation")
      expect(html).to include("bg-amber-50").or include("amber")
    end

    it "returns red badge for nominee_detected" do
      warning = build(:kyc_validation_warning, warning_type: :nominee_detected)
      html = presenter.warning_type_badge(warning)
      expect(html).to include("Nominee")
      expect(html).to include("bg-red-50").or include("red")
    end

    it "returns amber badge for unresolved_chain" do
      warning = build(:kyc_validation_warning, warning_type: :unresolved_chain)
      html = presenter.warning_type_badge(warning)
      expect(html).to include("Unresolved")
      expect(html).to include("bg-amber-50").or include("amber")
    end

    it "returns blue badge for ubo_threshold_exceeded" do
      warning = build(:kyc_validation_warning, warning_type: :ubo_threshold_exceeded)
      html = presenter.warning_type_badge(warning)
      expect(html).to include("UBO")
      expect(html).to include("bg-blue-50").or include("blue")
    end
  end

  describe "#warning_detail" do
    it "formats percentage_deviation detail" do
      warning = build(:kyc_validation_warning, warning_type: :percentage_deviation,
                      metadata: { expected: 100.0, actual: 98.16, deviation: 1.84 })
      detail = presenter.warning_detail(warning)
      expect(detail).to include("Expected 100.0%")
      expect(detail).to include("actual 98.16%")
      expect(detail).to include("deviation: 1.84%")
    end

    it "formats nominee_detected detail" do
      warning = build(:kyc_validation_warning, warning_type: :nominee_detected,
                      metadata: { detection_reason: "keyword_match", jurisdiction: "BVI" })
      detail = presenter.warning_detail(warning)
      expect(detail).to include("Reason: Keyword match")
      expect(detail).to include("Jurisdiction: BVI")
    end

    it "formats unresolved_chain detail" do
      warning = build(:kyc_validation_warning, warning_type: :unresolved_chain,
                      metadata: { entity_name: "Test Corp" })
      detail = presenter.warning_detail(warning)
      expect(detail).to include("Corporate entity with no traced individual owner")
    end

    it "formats ubo_threshold_exceeded detail" do
      warning = build(:kyc_validation_warning, warning_type: :ubo_threshold_exceeded,
                      metadata: { effective_percentage: 30.0, threshold: 25.0, individual_name: "Test Person" })
      detail = presenter.warning_detail(warning)
      expect(detail).to include("30.0% effective ownership")
      expect(detail).to include("threshold: 25.0%")
    end
  end
end
