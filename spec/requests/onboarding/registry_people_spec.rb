# frozen_string_literal: true

require "rails_helper"

# MH-417: Yes or No on a person the registry lists.
RSpec.describe "Onboarding registry people", type: :request do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets", registry_jurisdiction: "gb") }
  let(:applicant_user) { create(:applicant_user, applicant: applicant) }
  let(:profile) { create(:registry_profile, applicant: applicant, company_name: "ACME WIDGETS LIMITED") }
  let(:session) do
    create(:onboarding_session, applicant: applicant, current_stage: :directors_ubos,
                                stage_data: { "company_info" => { "company_name" => "Acme Widgets" },
                                              "registry_check" => { "state" => "confirmed", "profile_id" => profile.id } })
  end

  before do
    sign_in applicant_user, scope: :applicant_user
    create(:registry_director, registry_profile: profile, name: "DOE, Jane")
    create(:registry_director, registry_profile: profile, name: "ROE, Rita")
    create(:onboarding_message, onboarding_session: session, role: :bot,
                                content: Onboarding::RegistryPeople.begin!(session))
  end

  describe "GET /portal/onboarding" do
    it "shows the person with Yes and No buttons instead of chips" do
      get portal_onboarding_path

      page = Capybara.string(response.body)
      expect(page).to have_text("The registry lists Jane Doe as a director. Is that you or someone involved in the business?")
      expect(page.find("#onboarding_quick_replies [data-testid='registry-person-yes']")).to have_text("Yes, that's them")
      expect(page.find("#onboarding_quick_replies [data-testid='registry-person-no']")).to have_text("No, not involved")
    end

    it "does not show the buttons while the applicant's own message is the latest" do
      create(:onboarding_message, onboarding_session: session, role: :applicant, content: "hello")

      get portal_onboarding_path

      expect(Capybara.string(response.body)).to have_no_css("[data-testid='registry-person-yes']")
    end
  end

  describe "POST /portal/onboarding/registry_person" do
    it "on yes asks for the missing details" do
      post portal_onboarding_registry_person_path, params: { answer: "yes" }

      expect(response).to redirect_to(portal_onboarding_path)
      expect(session.onboarding_messages.bot.order(:created_at).last.content)
        .to eq("Thanks. What are Jane Doe's date of birth and nationality?")
    end

    it "on no records the dispute and offers the next person, without creating a principal" do
      post portal_onboarding_registry_person_path, params: { answer: "no" }

      expect(applicant.data_conflicts.status_open.where(field: "involvement").count).to eq(1)
      expect(applicant.kyc_principals).to be_empty
      expect(session.onboarding_messages.bot.order(:created_at).last.content).to include("**Rita Roe**")
    end

    it "does not ask again after a reload, and ignores a second answer while details are being collected" do
      post portal_onboarding_registry_person_path, params: { answer: "yes" }
      get portal_onboarding_path

      expect(Capybara.string(response.body)).to have_no_css("[data-testid='registry-person-yes']")
      expect { post portal_onboarding_registry_person_path, params: { answer: "no" } }.not_to change(OnboardingMessage, :count)
    end

    it "rejects an unknown answer" do
      post portal_onboarding_registry_person_path, params: { answer: "maybe" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires a signed-in applicant" do
      sign_out :applicant_user

      post portal_onboarding_registry_person_path, params: { answer: "yes" }

      expect(response).to redirect_to(new_applicant_user_session_path)
    end
  end
end
