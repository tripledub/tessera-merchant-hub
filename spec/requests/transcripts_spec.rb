# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Transcripts", type: :request do
  let(:psp_admin) { create(:user, :psp_admin) }
  let(:psp_support) { create(:user, :psp_support) }
  let(:merchant_admin) { create(:user, :merchant_admin) }
  let!(:session) { create(:onboarding_session) }

  describe "GET /transcripts" do
    it "lists onboarding sessions for a PSP admin" do
      sign_in psp_admin

      get transcripts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Transcripts", "Applicant", "Status", "Current stage",
        "Messages", "Started", "Last activity", "Elapsed", session.applicant.name)
      expect(response.body).to include("Filter transcripts", "All applicants", "All statuses", "All stages")
    end

    it "lists onboarding sessions for PSP support" do
      sign_in psp_support

      get transcripts_path

      expect(response).to have_http_status(:ok)
    end

    it "filters sessions" do
      other_session = create(:onboarding_session, status: :completed)
      sign_in psp_admin

      get transcripts_path, params: { status: "completed" }

      expect(response.body).to include(other_session.applicant.name)
      expect(response.body).to include(transcript_path(other_session))
      expect(response.body).not_to include(transcript_path(session))
    end

    it "returns forbidden to merchant users" do
      sign_in merchant_admin

      get transcripts_path

      expect(response).to have_http_status(:forbidden)
    end

    it "redirects unauthenticated users to sign in" do
      get transcripts_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the no-session empty state" do
      session.destroy!
      sign_in psp_admin

      get transcripts_path

      expect(response.body).to include("No onboarding sessions yet")
    end

    it "shows a filtered empty state" do
      sign_in psp_admin

      get transcripts_path, params: { status: "abandoned" }

      expect(response.body).to include("No sessions match these filters", "Clear filters")
    end
  end

  describe "GET /transcripts/:id" do
    before do
      create(:onboarding_message, onboarding_session: session, role: :bot,
        content: "Welcome", created_at: 2.minutes.ago)
      create(:onboarding_message, onboarding_session: session, role: :applicant,
        content: "Here are my details", created_at: 1.minute.ago)
    end

    it "shows a transcript to PSP support" do
      sign_in psp_support

      get transcript_path(session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(session.applicant.name, "Welcome", "Here are my details")
      expect(response.body).to include("Session overview", "Progress", "Messages", "Applicant messages",
        "Chatbot messages", "Started", "Last activity", "Elapsed", "Company info")
      expect(response.body.index("Welcome")).to be < response.body.index("Here are my details")
    end

    it "renders bot Markdown and strips unsafe HTML" do
      create(:onboarding_message, onboarding_session: session, role: :bot,
        content: "**Important** <script>alert('x')</script>")
      sign_in psp_support

      get transcript_path(session)

      expect(response.body).to include("<strong>Important</strong>")
      expect(response.body).not_to include("<script>alert('x')</script>")
    end

    it "shows an empty transcript state when there are no messages" do
      session.onboarding_messages.destroy_all
      sign_in psp_support

      get transcript_path(session)

      expect(response.body).to include("This session has no messages")
    end

    it "returns forbidden to merchant users" do
      sign_in merchant_admin

      get transcript_path(session)

      expect(response).to have_http_status(:forbidden)
    end

    it "returns not found for an unknown session" do
      sign_in psp_admin

      get transcript_path(SecureRandom.uuid)

      expect(response).to have_http_status(:not_found)
    end
  end
end
