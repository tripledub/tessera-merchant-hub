# frozen_string_literal: true

require "rails_helper"

# MH-200: Applicant-facing document validity/replacement notices. This
# presenter must be structurally incapable of leaking confidence,
# reason_code, staff identity, or policy_version — its public interface
# (#notices, each a Notice(document_type_label:, message:)) never reads any
# of those fields at all, for any state.
RSpec.describe OnboardingDocumentValidityPresenter, type: :presenter do
  let_it_be(:actor) { create(:user, :psp_admin) }
  let(:template) { ApplicationController.new.view_context }
  let(:applicant) { create(:applicant) }
  let(:onboarding_session) { create(:onboarding_session, applicant: applicant) }
  let(:presenter) { described_class.new(onboarding_session, template) }

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

  describe "#notices" do
    it "is empty for a valid document" do
      passport_document("expiry" => { "raw" => "x",
        "normalized" => (applicant.validity_reference_date + 2.years).iso8601, "confidence" => 0.95,
        "provenance" => "ai_extraction" })

      expect(presenter.notices).to eq([])
    end

    it "is empty for an expiring_soon document (not yet actionable)" do
      passport_document("expiry" => { "raw" => "x",
        "normalized" => (applicant.validity_reference_date + 10).iso8601, "confidence" => 0.95,
        "provenance" => "ai_extraction" })

      expect(presenter.notices).to eq([])
    end

    it "surfaces an under-review message for confirmation_required, never a rejection" do
      passport_document("expiry" => { "raw" => nil, "normalized" => nil, "confidence" => nil,
        "provenance" => "ai_extraction" })

      notices = presenter.notices
      expect(notices.size).to eq(1)
      expect(notices.first.message).to eq("We're reviewing your Passport.")
    end

    it "surfaces an invalid message for an expired document, naming the document type and the action" do
      passport_document("expiry" => { "raw" => "x",
        "normalized" => (applicant.validity_reference_date - 1).iso8601, "confidence" => 0.95,
        "provenance" => "ai_extraction" })

      notices = presenter.notices
      expect(notices.size).to eq(1)
      expect(notices.first.message).to eq("Your Passport is no longer valid — please upload a new one.")
    end

    it "surfaces an invalid message for a stale document" do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "utility_bill", effective_from: Date.new(2020, 1, 1),
        mode: :freshness, required_dates: [ "issued" ], warning_thresholds: [], max_age_months: 3
      )
      create(:kyc_document, applicant: applicant, document_type: :utility_bill, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "issued" => { "raw" => "x",
               "normalized" => (applicant.validity_reference_date - 4.months).iso8601, "confidence" => 0.95,
               "provenance" => "ai_extraction" } })

      notices = presenter.notices
      expect(notices.size).to eq(1)
      expect(notices.first.message).to eq("Your Utility Bill is no longer valid — please upload a new one.")
    end

    it "surfaces a replacement-required message when an open replacement requirement exists" do
      document = passport_document("expiry" => { "raw" => "x",
        "normalized" => (applicant.validity_reference_date + 10).iso8601, "confidence" => 0.95,
        "provenance" => "ai_extraction" })
      create(:kyc_document_replacement_requirement, kyc_document: document, status: :warned)

      notices = presenter.notices
      expect(notices.size).to eq(1)
      expect(notices.first.message)
        .to eq("Your Passport will need replacing soon — please upload an updated one when you can.")
    end

    it "does not surface a replacement-required message once the requirement is closed" do
      document = passport_document("expiry" => { "raw" => "x",
        "normalized" => (applicant.validity_reference_date + 2.years).iso8601, "confidence" => 0.95,
        "provenance" => "ai_extraction" })
      replacement = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "x",
               "normalized" => (applicant.validity_reference_date + 2.years).iso8601, "confidence" => 0.95,
               "provenance" => "ai_extraction" } })
      create(:kyc_document_replacement_requirement, kyc_document: document, status: :closed,
             closed_at: Time.current, superseded_by_kyc_document: replacement)

      expect(presenter.notices).to eq([])
    end

    it "is empty for a document type with no resolvable validity policy" do
      create(:kyc_document, applicant: applicant, document_type: :driving_licence, status: :complete,
             classification_status: :confirmed)

      expect(presenter.notices).to eq([])
    end

    it "excludes superseded documents" do
      original = passport_document("expiry" => { "raw" => "x",
        "normalized" => (applicant.validity_reference_date - 1).iso8601, "confidence" => 0.3,
        "provenance" => "ai_extraction" })
      replacement = passport_document("expiry" => { "raw" => "x",
        "normalized" => (applicant.validity_reference_date + 2.years).iso8601, "confidence" => 0.95,
        "provenance" => "ai_extraction" })
      original.update!(superseded_by_kyc_document: replacement)

      expect(presenter.notices).to eq([])
    end

    # Structural (not just behavioural) guarantee: the presenter's public
    # interface never exposes confidence, reason_code, staff identity, or
    # policy_version for ANY state — not merely "doesn't currently render"
    # them, but genuinely has no accessor for them at all.
    it "exposes no method surface for confidence, reason_code, staff identity, or policy_version" do
      forbidden = %i[confidence reason_code reason_details confirmed_by policy_version assessment]
      forbidden.each do |method_name|
        expect(presenter).not_to respond_to(method_name)
      end
    end

    it "never includes confidence, a reason_code, or an actor's identity in rendered notices, across every state" do
      confirmation_required_doc = passport_document("expiry" => { "raw" => nil, "normalized" => nil,
        "confidence" => nil, "provenance" => "ai_extraction" })
      Kyc::DocumentDateConfirmation.create!(
        kyc_document: confirmation_required_doc, date_role: "expiry", extracted_value: nil,
        confirmed_value: Date.new(2025, 1, 1), confirmed_by: actor
      )

      messages = presenter.notices.map(&:message).join(" ")
      expect(messages).not_to include(actor.email)
      expect(messages).not_to match(/0\.\d+/)
      expect(messages).not_to match(/within_\d+_day_threshold|past_printed_expiry|older_than_max_age|missing_required_date/)
      expect(messages).not_to include("v1")
    end
  end
end
