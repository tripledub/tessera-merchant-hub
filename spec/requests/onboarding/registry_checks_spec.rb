# frozen_string_literal: true

require "rails_helper"

# MH-391: Yes or No on the company the registry found for the applicant's number.
RSpec.describe "Onboarding registry check", type: :request do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets", company_number: nil, registry_jurisdiction: "gb") }
  let(:applicant_user) { create(:applicant_user, applicant: applicant) }
  let(:session) do
    create(:onboarding_session, applicant: applicant, current_stage: :company_info,
                                stage_data: { "company_info" => { "company_name" => "Acme Widgets",
                                                                  "company_type" => "limited_company",
                                                                  "country_of_incorporation" => "United Kingdom",
                                                                  "registration_number" => "12345678" } })
  end
  let(:profile) do
    create(:registry_profile, applicant: applicant, company_name: "ACME WIDGETS LIMITED", company_number: "12345678")
  end

  before do
    sign_in applicant_user, scope: :applicant_user
    create(:registry_address, registry_profile: profile)
    allow(Registry::Lookup).to receive(:call).and_return(Registry::Lookup::Result.success(profile))
    Onboarding::RegistryCompanyCheck.run!(session)
    create(:onboarding_message, onboarding_session: session, role: :bot,
                                content: Onboarding::RegistryCompanyCheck.prompt(session))
  end

  describe "GET /portal/onboarding" do
    it "shows the match with Yes and No buttons instead of chips" do
      get portal_onboarding_path

      page = Capybara.string(response.body)
      expect(page).to have_text("I found ACME WIDGETS LIMITED, active, registered at 10 Business Park, Bristol, BS1 1AA (Companies House). Is this your company?")
      expect(page.find("#onboarding_quick_replies [data-testid='registry-check-yes']")).to have_text("Yes, that's it")
      expect(page.find("#onboarding_quick_replies [data-testid='registry-check-no']")).to have_text("No, not mine")
      expect(page).to have_no_css("#onboarding_quick_replies .kyn-chip")
    end

    it "does not show the buttons while the applicant's own message is the latest" do
      create(:onboarding_message, onboarding_session: session, role: :applicant, content: "hello")

      get portal_onboarding_path

      expect(Capybara.string(response.body)).to have_no_css("[data-testid='registry-check-yes']")
    end
  end

  describe "POST /portal/onboarding/registry_check" do
    it "on yes saves the registry's details and carries on" do
      post portal_onboarding_registry_check_path, params: { answer: "yes" }

      expect(response).to redirect_to(portal_onboarding_path)
      expect(applicant.reload.company_name).to eq("ACME WIDGETS LIMITED")
      expect(session.reload.stage_data["company_info"]).to include("registered_address" => "10 Business Park, Bristol, BS1 1AA")
      expect(session.onboarding_messages.bot.order(:created_at).last.content).to include("Thanks")
    end

    it "on yes completes the company details and moves on to the directors when nothing else is missing" do
      post portal_onboarding_registry_check_path, params: { answer: "yes" }

      expect(session.reload.current_stage).to eq("directors_ubos")
      expect(session.onboarding_messages.bot.order(:created_at).last.content).to include("Next, let’s add the directors")
    end

    it "on no keeps what the applicant typed and asks for the address" do
      post portal_onboarding_registry_check_path, params: { answer: "no" }

      expect(applicant.reload.company_name).to eq("Acme Widgets")
      expect(session.reload.stage_data["company_info"]).to include("company_name" => "Acme Widgets")
      expect(session.onboarding_messages.bot.order(:created_at).last.content).to include("registered address")
    end

    it "does not ask again after a reload" do
      post portal_onboarding_registry_check_path, params: { answer: "no" }
      get portal_onboarding_path

      expect(Capybara.string(response.body)).to have_no_css("[data-testid='registry-check-yes']")
    end

    it "ignores a second answer" do
      post portal_onboarding_registry_check_path, params: { answer: "no" }

      expect { post portal_onboarding_registry_check_path, params: { answer: "yes" } }
        .not_to change(OnboardingMessage, :count)
    end

    it "rejects an unknown answer" do
      post portal_onboarding_registry_check_path, params: { answer: "maybe" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires a signed-in applicant" do
      sign_out :applicant_user

      post portal_onboarding_registry_check_path, params: { answer: "yes" }

      expect(response).to redirect_to(new_applicant_user_session_path)
    end
  end
end
