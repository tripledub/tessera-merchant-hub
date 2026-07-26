# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding conversations", type: :request do
  describe "GET /portal/onboarding" do
    it "redirects unauthenticated applicants to sign in" do
      get portal_onboarding_path

      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    it "renders the applicant chat page with a welcome message" do
      applicant_user = create(:applicant_user)
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("KYC onboarding")
      expect(response.body).to include("Welcome")
      expect(response.body).to include("data-controller=\"onboarding-chat\"")
      expect(response.body).to include("data-onboarding-chat-session-id-value=")
      expect(response.body).to include("data-onboarding-chat-target=\"typing\"")
      expect(response.body).to include("turbo-cable-stream-source")
    end

    it "renders existing messages with bot on the left and applicant on the right" do
      applicant_user = create(:applicant_user)
      session = create(:onboarding_session, applicant: applicant_user.applicant)
      create(:onboarding_message, onboarding_session: session, role: :bot, content: "Hello")
      create(:onboarding_message, onboarding_session: session, role: :applicant, content: "Hi")
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).to include("justify-start")
      expect(response.body).to include("justify-end")
      expect(response.body).to include("Hello")
      expect(response.body).to include("Hi")
    end

    it "renders the current stage in the progress indicator" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :business_activity)
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).to include("data-testid=\"onboarding-progress\"")
      expect(response.body).to include("aria-current=\"step\"")
      expect(response.body).to include("Business activity")
    end

    it "shows the document upload button from the document collection stage" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).to include("data-testid=\"document-upload-button\"")
    end

    it "hides the document upload button before the document collection stage" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :company_info)
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).not_to include("data-testid=\"document-upload-button\"")
    end

    it "shows outstanding checklist items with a defer button" do
      applicant_user = create(:applicant_user)
      create(:kyc_principal, applicant: applicant_user.applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).to include("Proof of identity for Jane Smith")
      expect(response.body).to include("data-testid=\"defer-document-button\"")
    end

    it "hides the checklist strip when there are no outstanding items" do
      applicant_user = create(:applicant_user)
      session = create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :company_info)
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).not_to include("data-testid=\"defer-document-button\"")
    end

    it "gives each defer button a distinguishing accessible name" do
      applicant_user = create(:applicant_user)
      create(:kyc_principal, applicant: applicant_user.applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).to include("aria-label=\"Can&#39;t upload Proof of identity for Jane Smith now\"")
    end
  end

  describe "POST /portal/onboarding/messages" do
    it "enqueues a streaming job and returns 200 OK" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant)
      sign_in applicant_user, scope: :applicant_user

      post portal_onboarding_messages_path, params: { message: "Hello" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_blank
      expect(StreamOnboardingResponseJob).to have_been_enqueued.with(anything, "Hello")
    end

    it "redirects unauthenticated applicants to sign in" do
      post portal_onboarding_messages_path, params: { message: "Hello" }

      expect(response).to redirect_to(new_applicant_user_session_path)
    end
  end

  describe "POST /portal/onboarding/documents" do
    let(:file) { fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.pdf"), "application/pdf") }

    it "redirects unauthenticated applicants to sign in" do
      post portal_onboarding_documents_path

      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    it "uploads a KYC document for the signed-in applicant" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      sign_in applicant_user, scope: :applicant_user

      expect {
        post portal_onboarding_documents_path(format: :turbo_stream), params: {
          kyc_document: { files: [ file ] }
        }
      }.to change(KycDocument, :count).by(1)
        .and have_enqueued_job(ClassifyKycDocumentJob)

      expect(response.media_type).to eq Mime[:turbo_stream]
      expect(response.body).to include("Uploaded 1 document")
      expect(KycDocument.last.applicant).to eq(applicant_user.applicant)
    end

    it "returns an upload prompt when no files are selected" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      sign_in applicant_user, scope: :applicant_user

      post portal_onboarding_documents_path(format: :turbo_stream), params: { kyc_document: { files: [] } }

      expect(response.body).to include("Choose at least one file")
    end
  end
end
