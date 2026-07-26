# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding document deferrals", type: :request do
  describe "POST /portal/onboarding/document_deferrals" do
    it "redirects unauthenticated applicants to sign in" do
      post portal_onboarding_document_deferrals_path, params: { index: 0 }

      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    it "defers the item and posts a confirmation message" do
      applicant_user = create(:applicant_user)
      applicant = applicant_user.applicant
      create(:kyc_principal, applicant: applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      sign_in applicant_user, scope: :applicant_user

      identity_index = Onboarding::DocumentCollectionService.received_documents(session)
        .find_index { |i| i["category"] == "identity" }

      expect {
        post portal_onboarding_document_deferrals_path(format: :turbo_stream), params: { index: identity_index }
      }.to change(OnboardingMessage, :count).by(1)

      expect(response.media_type).to eq Mime[:turbo_stream]
      expect(response.body).to include("Noted")
      expect(response.body).to include("Proof of identity for Jane Smith")
      expect(session.reload.document_checklist[identity_index]["deferred"]).to be true
    end

    it "posts a closing message once every remaining item is received or deferred" do
      applicant_user = create(:applicant_user)
      applicant = applicant_user.applicant
      create(:kyc_principal, applicant: applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      sign_in applicant_user, scope: :applicant_user

      # 3 items here: identity + proof_of_address for Jane Smith, plus the
      # always-present business_address_items entry. Defer each index in turn so
      # every item is individually addressed rather than re-deferring the same one.
      total_items = Onboarding::DocumentCollectionService.received_documents(session).size
      last_body = nil
      total_items.times do |index|
        post portal_onboarding_document_deferrals_path(format: :turbo_stream), params: { index: index }
        last_body = response.body
      end

      expect(last_body).to include("You're all set for now")
      expect(session.reload.status).to eq("in_progress")
    end

    it "does nothing when the item is already received" do
      applicant_user = create(:applicant_user)
      applicant = applicant_user.applicant
      principal = create(:kyc_principal, applicant: applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)
      identity_index = Onboarding::DocumentCollectionService.received_documents(session)
        .find_index { |i| i["category"] == "identity" }
      sign_in applicant_user, scope: :applicant_user

      expect {
        post portal_onboarding_document_deferrals_path(format: :turbo_stream), params: { index: identity_index }
      }.not_to change(OnboardingMessage, :count)
    end

    it "does nothing for a negative index" do
      applicant_user = create(:applicant_user)
      applicant = applicant_user.applicant
      create(:kyc_principal, applicant: applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      sign_in applicant_user, scope: :applicant_user

      expect {
        post portal_onboarding_document_deferrals_path(format: :turbo_stream), params: { index: -1 }
      }.not_to change(OnboardingMessage, :count)

      expect(session.reload.document_checklist.last["deferred"]).to be false
    end

    it "does nothing for a non-numeric index" do
      applicant_user = create(:applicant_user)
      applicant = applicant_user.applicant
      create(:kyc_principal, applicant: applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      sign_in applicant_user, scope: :applicant_user

      expect {
        post portal_onboarding_document_deferrals_path(format: :turbo_stream), params: { index: "abc" }
      }.not_to change(OnboardingMessage, :count)

      expect(session.reload.document_checklist[0]["deferred"]).to be false
    end

    it "does not raise when the applicant has no onboarding session yet" do
      applicant_user = create(:applicant_user)
      sign_in applicant_user, scope: :applicant_user

      expect {
        post portal_onboarding_document_deferrals_path(format: :turbo_stream), params: { index: 0 }
      }.not_to raise_error

      expect(response).to have_http_status(:ok)
    end
  end
end
