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

    it "names the company on the buttons, so the applicant can see what they are agreeing to (MH-415)" do
      get portal_onboarding_path

      page = Capybara.string(response.body)
      expect(page.find("[data-testid='company-confirmation-yes']")).to have_text("Yes, Acme Widgets Ltd")
      expect(page.find("[data-testid='company-confirmation-no']")).to have_text("No, a different name")
    end

    it "confirms the name the PSP gave when the applicant has not declared one yet, instead of asking for it (MH-415)" do
      applicant.update!(name: "Stew & Co", company_name: nil, company_number: nil)

      get portal_onboarding_path

      page = Capybara.string(response.body)
      expect(page).to have_text("I have your company as Stew & Co. Is this correct?")
      expect(page.find("[data-testid='company-confirmation-yes']")).to have_text("Yes, Stew & Co")
      expect(response.body).not_to include("please tell us the name of your business")
    end

    it "carries on from the confirmed PSP name: saved as the applicant's answer, so the form agrees (MH-415)" do
      applicant.update!(name: "Stew & Co", company_name: nil, company_number: nil)

      post portal_onboarding_company_confirmation_path, params: { answer: "yes" }

      expect(applicant.reload.company_name).to eq("Stew & Co")
      expect(applicant.name).to eq("Stew & Co")
      get portal_application_path(step: "company")
      expect(Capybara.string(response.body)).to have_field("onboarding_application[applicant_attributes][company_name]", with: "Stew & Co")
      expect(Capybara.string(response.body)).to have_no_text("We've used the name we have on file")
    end

    it "asks for the name when the applicant says no to the PSP's name (MH-415)" do
      applicant.update!(name: "Stew & Co", company_name: nil, company_number: nil)

      post portal_onboarding_company_confirmation_path, params: { answer: "no" }

      expect(applicant.reload.company_name).to be_nil
      expect(applicant.onboarding_session.onboarding_messages.bot.last.content).to include("name of your business")
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
