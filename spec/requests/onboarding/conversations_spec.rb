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
  end
end
