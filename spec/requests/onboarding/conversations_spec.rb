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
  end

  describe "POST /portal/onboarding/messages" do
    it "submits a message through the conversation engine" do
      applicant_user = create(:applicant_user)
      session = create(:onboarding_session, applicant: applicant_user.applicant)
      sign_in applicant_user, scope: :applicant_user
      allow(Onboarding::ConversationEngine).to receive(:respond).and_return(
        bot_message: "Tell me your company name.",
        extracted_data: {},
        stage_changed: false
      )

      post portal_onboarding_messages_path(format: :turbo_stream), params: { message: "Hello" }

      expect(response.media_type).to eq Mime[:turbo_stream]
      expect(response.body).to include("Tell me your company name.")
      expect(Onboarding::ConversationEngine).to have_received(:respond).with(
        session: session,
        user_message: "Hello"
      )
    end

    it "replaces the optimistic applicant preview with the persisted applicant message" do
      applicant_user = create(:applicant_user)
      session = create(:onboarding_session, applicant: applicant_user.applicant)
      sign_in applicant_user, scope: :applicant_user
      allow(Onboarding::ConversationEngine).to receive(:respond) do |session:, user_message:|
        create(:onboarding_message, onboarding_session: session, role: :applicant, content: user_message)
        create(:onboarding_message, onboarding_session: session, role: :bot, content: "Tell me your company name.")
        { bot_message: "Tell me your company name.", extracted_data: {}, stage_changed: false }
      end

      post portal_onboarding_messages_path(format: :turbo_stream), params: { message: "Hello" }

      expect(response.body).to include('action="replace" target="onboarding_pending_applicant_message"')
      expect(response.body).to include("Hello")
    end

    it "broadcasts persisted bot replies over the onboarding stream" do
      applicant_user = create(:applicant_user)
      session = create(:onboarding_session, applicant: applicant_user.applicant)
      sign_in applicant_user, scope: :applicant_user
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      bot_messages = []
      stub_persisted_bot_reply(bot_messages)

      post portal_onboarding_messages_path(format: :turbo_stream), params: { message: "Hello" }

      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
        session,
        target: "onboarding_messages",
        partial: "onboarding/conversations/message",
        locals: { message: bot_messages.first }
      )
    end

    it "refreshes stage progress when the response advances the session" do
      applicant_user = create(:applicant_user)
      session = create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :company_info)
      sign_in applicant_user, scope: :applicant_user
      allow(Onboarding::ConversationEngine).to receive(:respond) do
        session.update!(current_stage: :directors_ubos, completed_stages: [ "company_info" ])
        { bot_message: "Now tell me about directors.", extracted_data: {}, stage_changed: true }
      end

      post portal_onboarding_messages_path(format: :turbo_stream), params: { message: "Done" }

      expect(response.body).to include('target="onboarding_progress"')
      expect(response.body).to include('target="onboarding_stage_badge"')
      expect(response.body).to include("Directors ubos")
    end

    it "refreshes the composer when the response advances to document collection" do
      applicant_user = create(:applicant_user)
      session = create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :jurisdictions)
      sign_in applicant_user, scope: :applicant_user
      allow(Onboarding::ConversationEngine).to receive(:respond) do
        session.update!(current_stage: :document_collection, completed_stages: [ "jurisdictions" ])
        { bot_message: "Next, upload your documents.", extracted_data: {}, stage_changed: true }
      end

      post portal_onboarding_messages_path(format: :turbo_stream), params: { message: "Only the UK" }

      expect(response.body).to include('target="onboarding_composer"')
      expect(response.body).to include('data-testid="document-upload-button"')
    end
  end

  def stub_persisted_bot_reply(bot_messages)
    allow(Onboarding::ConversationEngine).to receive(:respond) do |session:, user_message:|
      create(:onboarding_message, onboarding_session: session, role: :applicant, content: user_message)
      bot_messages << create(:onboarding_message, onboarding_session: session, role: :bot, content: "Broadcast reply")
      { bot_message: "Broadcast reply", extracted_data: {}, stage_changed: false }
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
