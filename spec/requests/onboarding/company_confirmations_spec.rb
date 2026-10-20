# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding company confirmation", type: :request do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets Ltd", company_number: "12345678") }
  let(:applicant_user) { create(:applicant_user, applicant: applicant) }

  before { sign_in applicant_user, scope: :applicant_user }

  describe "GET /portal/onboarding" do
    it "asks the applicant to confirm the company already on the application" do
      get portal_onboarding_path

      expect(response.body).to include("I have your company as")
      expect(response.body).to include("Acme Widgets Ltd")
      expect(response.body).to include("12345678")
      expect(response.body).to include("data-testid=\"company-confirmation-yes\"")
      expect(response.body).to include("data-testid=\"company-confirmation-no\"")
      expect(response.body).not_to include("please tell us the name of your business")
    end

    it "shows the usual welcome when the application has no company name" do
      applicant.update!(company_name: nil, company_number: nil)

      get portal_onboarding_path

      expect(response.body).to include("please tell us the name of your business")
      expect(response.body).not_to include("data-testid=\"company-confirmation-yes\"")
    end

    it "does not ask again once the applicant has answered" do
      post portal_onboarding_company_confirmation_path, params: { answer: "yes" }

      get portal_onboarding_path

      expect(response.body).not_to include("data-testid=\"company-confirmation-yes\"")
      expect(response.body).not_to include("I have your company as")
    end
  end

  describe "POST /portal/onboarding/company_confirmation" do
    it "confirms the company, records the answer and returns to the chat" do
      post portal_onboarding_company_confirmation_path, params: { answer: "yes" }

      expect(response).to redirect_to(portal_onboarding_path)
      session = applicant.reload.onboarding_session
      expect(session.stage_data["company_info"]).to eq(
        "company_name" => "Acme Widgets Ltd", "registration_number" => "12345678"
      )
      expect(session.onboarding_messages.bot.last.content).to include("Company type")
    end

    it "starts fresh when the applicant says the details are wrong" do
      post portal_onboarding_company_confirmation_path, params: { answer: "no" }

      expect(response).to redirect_to(portal_onboarding_path)
      session = applicant.reload.onboarding_session
      expect(session.stage_data["company_info"]).to be_nil
      expect(session.onboarding_messages.bot.last.content).to include("name of your business")
    end

    it "rejects an unknown answer" do
      post portal_onboarding_company_confirmation_path, params: { answer: "maybe" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(applicant.reload.onboarding_session&.stage_data.to_h).not_to include("company_identity_check")
    end

    it "shows a corrected name on the form after the applicant says no and gives new details in chat" do
      post portal_onboarding_company_confirmation_path, params: { answer: "no" }
      session = applicant.reload.onboarding_session
      Onboarding::DataCaptureService.call(
        session: session, extracted_data: { "company_name" => "Corrected Widgets Ltd", "registration_number" => "87654321" }
      )

      get portal_application_path(step: "company")

      expect(response.body).to include("Corrected Widgets Ltd")
      expect(response.body).to include("87654321")
      expect(response.body).not_to include("Acme Widgets Ltd")
    end

    it "requires a signed-in applicant" do
      sign_out :applicant_user

      post portal_onboarding_company_confirmation_path, params: { answer: "yes" }

      expect(response).to redirect_to(new_applicant_user_session_path)
    end
  end
end
