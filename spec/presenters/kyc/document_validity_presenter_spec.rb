# frozen_string_literal: true

require "rails_helper"

# MH-200: staff-facing presentation of a document's current validity
# assessment, policy version, plain-language reason, confirmation history,
# and replacement progress. Covers all five Kyc::DocumentValidityAssessment
# outcomes plus the distinct "no assessment exists" (out-of-rollout) case.
RSpec.describe Kyc::DocumentValidityPresenter, type: :presenter do
  let_it_be(:actor) { create(:user, :psp_admin) }
  let(:template) { ApplicationController.new.view_context }
  let(:applicant) { create(:applicant) }

  def build_presenter(document)
    described_class.new(document, template)
  end

  before do
    Kyc::DocumentValidityPolicy.publish!(
      document_type: "passport", effective_from: Date.new(2020, 1, 1),
      mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
    )
  end

  def passport_document(validity_dates)
    create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
           classification_status: :confirmed, validity_dates: validity_dates)
  end

  describe "#outcome_key and #outcome_label" do
    it "distinguishes valid" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date + 2.years).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.outcome_key).to eq("valid")
      expect(presenter.outcome_label).to eq("Valid")
    end

    it "distinguishes expiring_soon" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date + 10).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.outcome_key).to eq("expiring_soon")
      expect(presenter.outcome_label).to eq("Expiring soon")
    end

    it "distinguishes expired" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date - 1).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.outcome_key).to eq("expired")
      expect(presenter.outcome_label).to eq("Expired")
    end

    it "distinguishes stale" do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "utility_bill", effective_from: Date.new(2020, 1, 1),
        mode: :freshness, required_dates: [ "issued" ], warning_thresholds: [], max_age_months: 3
      )
      document = create(:kyc_document, applicant: applicant, document_type: :utility_bill, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "issued" => { "raw" => "x",
                                              "normalized" => (applicant.validity_reference_date - 4.months).iso8601,
                                              "confidence" => 0.95, "provenance" => "ai_extraction" } })
      presenter = build_presenter(document)

      expect(presenter.outcome_key).to eq("stale")
      expect(presenter.outcome_label).to eq("No longer current")
    end

    it "distinguishes confirmation_required" do
      document = passport_document(
        "expiry" => { "raw" => nil, "normalized" => nil, "confidence" => nil, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.outcome_key).to eq("confirmation_required")
      expect(presenter.outcome_label).to eq("Awaiting review")
    end

    it "distinguishes the no-assessment (out-of-rollout) case" do
      document = create(:kyc_document, applicant: applicant, document_type: :driving_licence, status: :complete,
             classification_status: :confirmed)
      presenter = build_presenter(document)

      expect(presenter.outcome_key).to eq("no_assessment")
      expect(presenter.outcome_label).to eq("Not tracked")
      expect(presenter.assessment).to be_nil
    end

    it "gives every state a distinct badge colour class" do
      states = {
        "valid" => passport_document("expiry" => { "raw" => "x",
          "normalized" => (applicant.validity_reference_date + 2.years).iso8601, "confidence" => 0.95,
          "provenance" => "ai_extraction" }),
        "expired" => passport_document("expiry" => { "raw" => "x",
          "normalized" => (applicant.validity_reference_date - 1).iso8601, "confidence" => 0.95,
          "provenance" => "ai_extraction" }),
        "confirmation_required" => passport_document("expiry" => { "raw" => nil, "normalized" => nil,
          "confidence" => nil, "provenance" => "ai_extraction" }),
        "no_assessment" => create(:kyc_document, applicant: applicant, document_type: :driving_licence,
          status: :complete, classification_status: :confirmed)
      }

      badges = states.transform_values { |doc| build_presenter(doc).outcome_badge }
      expect(badges.values.uniq.size).to eq(badges.size)
    end
  end

  describe "#policy_version" do
    it "exposes the policy version behind the current assessment" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date + 2.years).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.policy_version).to eq(1)
    end

    it "is nil when there is no assessment" do
      document = create(:kyc_document, applicant: applicant, document_type: :driving_licence, status: :complete,
             classification_status: :confirmed)
      presenter = build_presenter(document)

      expect(presenter.policy_version).to be_nil
    end
  end

  describe "#reason_text" do
    it "renders a plain-language sentence for a static reason code" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date - 1).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.reason_text).to eq("Past the document's printed expiry date.")
    end

    it "renders a plain-language sentence for the dynamic within-threshold reason code" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date + 10).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.reason_text).to eq("Expires within 30 days (10 days remaining).")
    end

    it "is nil when there is no assessment" do
      document = create(:kyc_document, applicant: applicant, document_type: :driving_licence, status: :complete,
             classification_status: :confirmed)
      presenter = build_presenter(document)

      expect(presenter.reason_text).to be_nil
    end
  end

  describe "#replacement_requirement and #replacement_status_label" do
    it "is nil when no replacement requirement is open" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date + 2.years).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.replacement_requirement).to be_nil
      expect(presenter.replacement_status_label).to be_nil
    end

    it "surfaces the current replacement requirement's stage" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date + 10).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      create(:kyc_document_replacement_requirement, kyc_document: document, status: :escalated,
             escalated_at: Time.current)
      presenter = build_presenter(document)

      expect(presenter.replacement_requirement).to be_present
      expect(presenter.replacement_status_label).to eq("Replacement urgently required")
    end
  end

  describe "#confirmation_history" do
    it "is empty when nothing has been confirmed" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date + 2.years).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      presenter = build_presenter(document)

      expect(presenter.confirmation_history).to eq([])
    end

    it "lists confirmations across all roles, most recent first" do
      document = passport_document(
        "expiry" => { "raw" => "x", "normalized" => (applicant.validity_reference_date + 2.years).iso8601,
                      "confidence" => 0.95, "provenance" => "ai_extraction" }
      )
      first = Kyc::DocumentDateConfirmation.create!(
        kyc_document: document, date_role: "expiry", extracted_value: applicant.validity_reference_date + 2.years,
        confirmed_value: applicant.validity_reference_date + 2.years, confirmed_by: actor
      )
      second = travel_to(first.created_at + 1.minute) do
        Kyc::DocumentDateConfirmation.create!(
          kyc_document: document, date_role: "expiry", extracted_value: applicant.validity_reference_date + 2.years,
          confirmed_value: applicant.validity_reference_date + 3.years, confirmed_by: actor, reason: "Renewed"
        )
      end
      presenter = build_presenter(document)

      expect(presenter.confirmation_history).to eq([ second, first ])
    end
  end
end
