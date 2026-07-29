# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentValidityAssessment, type: :model do
  let_it_be(:document) { create(:kyc_document) }
  let_it_be(:policy) { create(:kyc_document_validity_policy) }

  def build_assessment(**overrides)
    described_class.new(
      {
        kyc_document: document,
        kyc_document_validity_policy: policy,
        policy_version: policy.version,
        assessed_at: Time.current,
        reference_date: Date.current,
        dates_used: { "expiry" => { "date" => "2030-01-01", "source" => "extracted" } },
        outcome: :valid,
        reason_code: "within_validity_window"
      }.merge(overrides)
    )
  end

  describe "validations" do
    it "is valid with all required fields" do
      expect(build_assessment).to be_valid
    end

    it { is_expected.to validate_presence_of(:policy_version) }
    it { is_expected.to validate_presence_of(:assessed_at) }
    it { is_expected.to validate_presence_of(:reference_date) }
    it { is_expected.to validate_presence_of(:outcome) }
    it { is_expected.to validate_presence_of(:reason_code) }
  end

  describe "immutability" do
    it "raises on update" do
      assessment = build_assessment.tap(&:save!)

      expect { assessment.update(reason_code: "changed") }.to raise_error(described_class::ImmutableError)
    end
  end

  describe ".current_for" do
    it "returns nil when no assessment exists" do
      expect(described_class.current_for(document)).to be_nil
    end

    it "returns the most recently created assessment" do
      older = build_assessment(assessed_at: 2.days.ago).tap(&:save!)
      newer = build_assessment(assessed_at: 1.day.ago).tap(&:save!)

      expect(described_class.current_for(document)).to eq(newer)
      expect(described_class.current_for(document)).not_to eq(older)
    end
  end
end
