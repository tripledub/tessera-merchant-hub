# frozen_string_literal: true

require "rails_helper"

# MH-198: Kyc::DocumentValidity::Assessor.assess_or_reuse is the single entry
# point completeness/readiness use to get a document's current validity
# state. Unlike .call (MH-197), which always appends a new historical row, it
# only calls through to .call (and thus creates a new assessment) when the
# resolved policy or the authoritative dates behind the last assessment have
# actually changed since. This is what keeps repeated readiness/completeness
# checks (every page load) from spamming Kyc::DocumentValidityAssessment.
RSpec.describe Kyc::DocumentValidity::Assessor, ".assess_or_reuse" do
  let(:reference_date) { Date.new(2026, 1, 1) }

  def validity_dates_for(normalized:, confidence: 0.95)
    { "raw" => normalized, "normalized" => normalized, "confidence" => confidence, "provenance" => "ai_extraction" }
  end

  context "without a resolvable policy" do
    it "returns nil and creates no assessment" do
      document = create(:kyc_document, document_type: "driving_licence")

      expect {
        result = described_class.assess_or_reuse(document: document, reference_date: reference_date)
        expect(result).to be_nil
      }.not_to change(Kyc::DocumentValidityAssessment, :count)
    end
  end

  context "with a resolvable policy and no prior assessment" do
    it "creates a new assessment" do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "passport", effective_from: Date.new(2025, 1, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
      )
      document = create(:kyc_document, document_type: "passport",
                         validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01") })

      expect {
        described_class.assess_or_reuse(document: document, reference_date: reference_date)
      }.to change(Kyc::DocumentValidityAssessment, :count).by(1)
    end
  end

  context "when called repeatedly with unchanged inputs" do
    before do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "passport", effective_from: Date.new(2025, 1, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
      )
    end

    it "reuses the existing assessment instead of creating a new one" do
      document = create(:kyc_document, document_type: "passport",
                         validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01") })

      first = described_class.assess_or_reuse(document: document, reference_date: reference_date)

      second = nil
      expect {
        second = described_class.assess_or_reuse(document: document, reference_date: reference_date)
      }.not_to change(Kyc::DocumentValidityAssessment, :count)

      expect(second).to eq(first)
      expect(Kyc::DocumentValidityAssessment.where(kyc_document: document).count).to eq(1)
    end

    it "reuses across many repeated calls (simulating multiple page loads)" do
      document = create(:kyc_document, document_type: "passport",
                         validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01") })

      5.times { described_class.assess_or_reuse(document: document, reference_date: reference_date) }

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: document).count).to eq(1)
    end
  end

  context "when the authoritative dates change since the last assessment" do
    before do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "passport", effective_from: Date.new(2025, 1, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
      )
    end

    it "creates a new assessment when a staff confirmation supersedes the extracted date" do
      document = create(:kyc_document, document_type: "passport",
                         validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01") })
      described_class.assess_or_reuse(document: document, reference_date: reference_date)

      actor = create(:user, :psp_admin)
      Kyc::DocumentDateConfirmation.create!(
        kyc_document: document, date_role: "expiry", confirmed_value: Date.new(2027, 6, 1),
        extracted_value: Date.new(2026, 12, 1), confirmed_by: actor, reason: "Corrected after re-check"
      )

      expect {
        described_class.assess_or_reuse(document: document, reference_date: reference_date)
      }.to change(Kyc::DocumentValidityAssessment, :count).by(1)
    end

    it "creates a new assessment when the document is re-extracted with no confirmation involved" do
      document = create(:kyc_document, document_type: "passport",
                         validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01") })
      described_class.assess_or_reuse(document: document, reference_date: reference_date)

      document.update!(validity_dates: { "expiry" => validity_dates_for(normalized: "2027-03-15") })

      second = nil
      expect {
        second = described_class.assess_or_reuse(document: document, reference_date: reference_date)
      }.to change(Kyc::DocumentValidityAssessment, :count).by(1)

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: document).count).to eq(2)
      expect(second.dates_used).to eq(
        "expiry" => { "date" => "2027-03-15", "source" => "extracted" }
      )
    end
  end

  context "when the reference date changes (a new application/review cycle)" do
    before do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "passport", effective_from: Date.new(2025, 1, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
      )
    end

    it "creates a new assessment rather than reusing the one for a different reference date" do
      document = create(:kyc_document, document_type: "passport",
                         validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01") })
      described_class.assess_or_reuse(document: document, reference_date: reference_date)

      expect {
        described_class.assess_or_reuse(document: document, reference_date: reference_date + 1)
      }.to change(Kyc::DocumentValidityAssessment, :count).by(1)
    end
  end

  context "when a newer policy version supersedes the one used for the last assessment" do
    it "creates a new assessment" do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "passport", effective_from: Date.new(2025, 1, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
      )
      document = create(:kyc_document, document_type: "passport",
                         validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01") })
      described_class.assess_or_reuse(document: document, reference_date: reference_date)

      Kyc::DocumentValidityPolicy.publish!(
        document_type: "passport", effective_from: Date.new(2025, 6, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 60 ]
      )

      expect {
        described_class.assess_or_reuse(document: document, reference_date: reference_date)
      }.to change(Kyc::DocumentValidityAssessment, :count).by(1)
    end
  end
end
