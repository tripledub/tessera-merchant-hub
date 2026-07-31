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

    it "shows a welcome-back message when returning with outstanding documents" do
      applicant_user = create(:applicant_user)
      create(:kyc_principal, applicant: applicant_user.applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      create(:onboarding_message, onboarding_session: session, role: :bot, content: "Here's what we need")
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      # generate_checklist produces 3 items here: identity + proof_of_address for
      # Jane Smith, plus the always-present business_address_items entry.
      expect(response.body).to include("Welcome back")
      expect(response.body).to include("3 documents outstanding")
    end

    it "does not show a welcome-back message on a brand new session" do
      applicant_user = create(:applicant_user)
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).not_to include("Welcome back")
    end

    # MH-200: applicant-facing document validity/replacement notices,
    # rendered on this same onboarding chat page since it is the only
    # applicant-facing surface in the app — both during and after
    # onboarding completes.
    context "with document validity notices" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport", effective_from: Date.new(2020, 1, 1),
          mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
        )
      end

      it "shows an under-review notice for a confirmation_required document, never a rejection" do
        applicant_user = create(:applicant_user)
        create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
        create(:kyc_document, applicant: applicant_user.applicant, document_type: :passport, status: :complete,
               classification_status: :confirmed,
               validity_dates: { "expiry" => { "raw" => nil, "normalized" => nil, "confidence" => nil,
                 "provenance" => "ai_extraction" } })
        sign_in applicant_user, scope: :applicant_user

        get portal_onboarding_path

        expect(response.body).to include("document-status-notices")
        expect(response.body).to include("We&#39;re reviewing your Passport.")
      end

      it "shows an invalid notice identifying the document and the required action" do
        applicant_user = create(:applicant_user)
        session = create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
        create(:kyc_document, applicant: applicant_user.applicant, document_type: :passport, status: :complete,
               classification_status: :confirmed,
               validity_dates: { "expiry" => { "raw" => "x",
                 "normalized" => (applicant_user.applicant.validity_reference_date - 1).iso8601, "confidence" => 0.95,
                 "provenance" => "ai_extraction" } })
        sign_in applicant_user, scope: :applicant_user

        get portal_onboarding_path

        expect(response.body).to include("Your Passport is no longer valid")
      end

      it "shows a replacement-required notice for an open replacement requirement" do
        applicant_user = create(:applicant_user)
        create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
        document = create(:kyc_document, applicant: applicant_user.applicant, document_type: :passport,
               status: :complete, classification_status: :confirmed,
               validity_dates: { "expiry" => { "raw" => "x",
                 "normalized" => (applicant_user.applicant.validity_reference_date + 10).iso8601,
                 "confidence" => 0.95, "provenance" => "ai_extraction" } })
        create(:kyc_document_replacement_requirement, kyc_document: document, status: :warned)
        sign_in applicant_user, scope: :applicant_user

        get portal_onboarding_path

        expect(response.body).to include("will need replacing soon")
      end

      it "does not show a notice for a valid document" do
        applicant_user = create(:applicant_user)
        create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
        create(:kyc_document, applicant: applicant_user.applicant, document_type: :passport, status: :complete,
               classification_status: :confirmed,
               validity_dates: { "expiry" => { "raw" => "x",
                 "normalized" => (applicant_user.applicant.validity_reference_date + 2.years).iso8601,
                 "confidence" => 0.95, "provenance" => "ai_extraction" } })
        sign_in applicant_user, scope: :applicant_user

        get portal_onboarding_path

        expect(response.body).not_to include("document-status-notices")
      end

      it "never leaks confidence, reason codes, or staff identity into the page" do
        psp_admin = create(:user, :psp_admin)
        applicant_user = create(:applicant_user)
        create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
        document = create(:kyc_document, applicant: applicant_user.applicant, document_type: :passport,
               status: :complete, classification_status: :confirmed,
               validity_dates: { "expiry" => { "raw" => nil, "normalized" => nil, "confidence" => nil,
                 "provenance" => "ai_extraction" } })
        Kyc::DocumentDateConfirmation.create!(
          kyc_document: document, date_role: "expiry", extracted_value: nil,
          confirmed_value: applicant_user.applicant.validity_reference_date - 1, confirmed_by: psp_admin
        )
        sign_in applicant_user, scope: :applicant_user

        get portal_onboarding_path

        expect(response.body).not_to include(psp_admin.email)
        expect(response.body).not_to include("missing_required_date")
        expect(response.body).not_to include("past_printed_expiry")
      end

      it "remains reachable, showing notices, after the onboarding session has completed" do
        applicant_user = create(:applicant_user)
        session = create(:onboarding_session, applicant: applicant_user.applicant,
               current_stage: :document_collection, status: :completed)
        create(:kyc_document, applicant: applicant_user.applicant, document_type: :passport, status: :complete,
               classification_status: :confirmed,
               validity_dates: { "expiry" => { "raw" => "x",
                 "normalized" => (applicant_user.applicant.validity_reference_date - 1).iso8601, "confidence" => 0.95,
                 "provenance" => "ai_extraction" } })
        sign_in applicant_user, scope: :applicant_user

        get portal_onboarding_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Your Passport is no longer valid")
      end
    end

    it "does not show a welcome-back message once nothing is outstanding" do
      applicant_user = create(:applicant_user)
      session = create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      # generate_checklist always includes one business_address_items entry even with
      # no principals/company_info/nominees — receive it so nothing remains outstanding.
      create(:kyc_document, applicant: applicant_user.applicant, document_type: :certificate_of_incorporation)
      create(:onboarding_message, onboarding_session: session, role: :bot, content: "Here's what we need")
      sign_in applicant_user, scope: :applicant_user

      get portal_onboarding_path

      expect(response.body).not_to include("Welcome back")
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

  describe "POST /portal/onboarding/messages with a control command" do
    include ActiveJob::TestHelper

    it "responds to help without calling inference" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :company_info)
      sign_in applicant_user, scope: :applicant_user
      adapter = instance_spy(Kyc::Inference::Base)
      allow(Kyc::Inference).to receive(:adapter).and_return(adapter)

      perform_enqueued_jobs do
        post portal_onboarding_messages_path, params: { message: "help" }
      end

      expect(adapter).not_to have_received(:generate)
      last_message = OnboardingMessage.order(:created_at).last
      expect(last_message).to have_attributes(role: "bot")
      expect(last_message.content).to include("help")
    end

    it "responds to save and quit by confirming progress is saved" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :business_activity)
      sign_in applicant_user, scope: :applicant_user

      perform_enqueued_jobs do
        post portal_onboarding_messages_path, params: { message: "save and quit" }
      end

      expect(OnboardingMessage.order(:created_at).last.content).to match(/saved/i)
    end

    it "blocks skip outside the document collection stage" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :company_info)
      sign_in applicant_user, scope: :applicant_user

      perform_enqueued_jobs do
        post portal_onboarding_messages_path, params: { message: "skip" }
      end

      expect(OnboardingMessage.order(:created_at).last.content).to match(/not available|isn.t available/i)
    end

    it "defers the first outstanding document when skip is used during document collection" do
      applicant_user = create(:applicant_user)
      applicant = applicant_user.applicant
      create(:kyc_principal, applicant: applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      sign_in applicant_user, scope: :applicant_user

      perform_enqueued_jobs do
        post portal_onboarding_messages_path, params: { message: "next" }
      end

      expect(OnboardingMessage.order(:created_at).last.content).to include("Noted")
      expect(session.reload.document_checklist.first["deferred"]).to be(true)
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

    it "names the uploaded file in the success message" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      sign_in applicant_user, scope: :applicant_user

      post portal_onboarding_documents_path(format: :turbo_stream), params: {
        kyc_document: { files: [ file ] }
      }

      expect(response.body).to include("sample.pdf")
    end

    it "gives a specific, actionable reason when a file type is unsupported" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      sign_in applicant_user, scope: :applicant_user
      unsupported = fixture_file_upload(Rails.root.join("spec/fixtures/files/unsupported.txt"), "text/plain")

      expect {
        post portal_onboarding_documents_path(format: :turbo_stream), params: {
          kyc_document: { files: [ unsupported ] }
        }
      }.not_to change(KycDocument, :count)

      expect(response.body).to include("unsupported.txt")
      expect(response.body).to include("unsupported type")
    end

    it "reports success and failure separately when uploading a mix of valid and invalid files" do
      applicant_user = create(:applicant_user)
      create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :document_collection)
      sign_in applicant_user, scope: :applicant_user
      unsupported = fixture_file_upload(Rails.root.join("spec/fixtures/files/unsupported.txt"), "text/plain")

      expect {
        post portal_onboarding_documents_path(format: :turbo_stream), params: {
          kyc_document: { files: [ file, unsupported ] }
        }
      }.to change(KycDocument, :count).by(1)

      expect(response.body).to include("sample.pdf")
      expect(response.body).to include("unsupported.txt")
      expect(response.body).to include("unsupported type")
    end
  end
end
