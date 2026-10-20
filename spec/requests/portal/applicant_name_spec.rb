# frozen_string_literal: true

require "rails_helper"

# MH-407: an optional name on the company details step, saved onto the signed-in
# applicant user so the dashboard can greet them. Names here are synthetic.
RSpec.describe "Portal applicant name", type: :request do
  let(:applicant_user) { create(:applicant_user, :nameless) }
  let!(:application) { create(:onboarding_application, applicant: applicant_user.applicant) }

  before { sign_in applicant_user, scope: :applicant_user }

  def company_params(names = nil)
    applicant = application.applicant
    params = {
      step: "company",
      onboarding_application: {
        business_model_description: "A specimen business model",
        operating_licence: "None required",
        applicant_attributes: {
          id: applicant.id, company_name: applicant.company_name, company_number: "12345678", sector: applicant.sector,
          primary_business_address_attributes: { line1: "1 Test Street", city: "Testford", postcode: "TE1 1ST", country: "United Kingdom" },
          trading_address_attributes: { line1: "2 Example Road", city: "Testford", postcode: "TE1 2ST", country: "United Kingdom" },
          applicant_domains_attributes: { "0" => { name: "specimen.example" } }
        }
      }
    }
    params[:applicant_user] = names unless names.nil?
    params
  end

  def page
    Capybara.string(response.body)
  end

  describe "the company details step" do
    it "shows optional first and last name fields at the top, with a hint and no required marker" do
      get portal_application_path(step: "company")

      first = page.find_field("applicant_user[first_name]")
      last = page.find_field("applicant_user[last_name]")
      expect(page).to have_content("Optional. We'll use it to greet you.")
      expect(page).to have_css("label", text: "First name")
      expect(page).to have_css("label", text: "Last name")
      expect(first["autocomplete"]).to eq("given-name")
      expect(last["autocomplete"]).to eq("family-name")
      expect([ first, last ].map { |field| field[:required] }).to all(be_blank)
      expect(response.body.index("applicant_user[first_name]")).to be < response.body.index("onboarding_application[applicant_attributes][company_name]")
    end

    it "pre-fills them from the signed-in user" do
      applicant_user.update!(first_name: "Alex", last_name: "Sample")

      get portal_application_path(step: "company")

      expect(page).to have_field("applicant_user[first_name]", with: "Alex")
      expect(page).to have_field("applicant_user[last_name]", with: "Sample")
    end
  end

  describe "saving the step" do
    it "saves the names onto the signed-in user, tidied, and carries on" do
      patch portal_application_path, params: company_params(first_name: "  Alex ", last_name: "Sample")

      expect(response).to redirect_to(portal_application_path(step: "fulfilment"))
      expect(applicant_user.reload).to have_attributes(first_name: "Alex", last_name: "Sample")
    end

    it "works exactly as before without a name, for a user with none" do
      patch portal_application_path, params: company_params(first_name: "", last_name: "")

      expect(response).to redirect_to(portal_application_path(step: "fulfilment"))
      expect(applicant_user.reload).to have_attributes(first_name: nil, last_name: nil)
      expect(application.reload.completed_steps).to include("company")
    end

    it "clears a name that was cleared in the form, storing nil" do
      applicant_user.update!(first_name: "Alex", last_name: "Sample")

      patch portal_application_path, params: company_params(first_name: "", last_name: "  ")

      expect(applicant_user.reload).to have_attributes(first_name: nil, last_name: nil)
    end

    it "leaves the names alone when the request carries none" do
      applicant_user.update!(first_name: "Alex", last_name: "Sample")

      patch portal_application_path, params: company_params

      expect(response).to redirect_to(portal_application_path(step: "fulfilment"))
      expect(applicant_user.reload).to have_attributes(first_name: "Alex", last_name: "Sample")
    end

    it "only changes the name that was sent" do
      applicant_user.update!(first_name: "Alex", last_name: "Sample")

      patch portal_application_path, params: company_params(first_name: "Sam")

      expect(applicant_user.reload).to have_attributes(first_name: "Sam", last_name: "Sample")
    end

    it "does not raise on odd values, and saves nothing from them" do
      applicant_user.update!(first_name: "Alex")

      [ { first_name: [ "Sam" ] }, { first_name: { "a" => "b" } }, "just a string", [ "x" ] ].each do |odd|
        patch portal_application_path, params: company_params(odd)

        expect(response).to have_http_status(:found).or have_http_status(:unprocessable_content)
      end
      expect(applicant_user.reload.first_name).to eq("Alex")
    end

    it "never changes another user's name for the same company" do
      colleague = create(:applicant_user, applicant: applicant_user.applicant, first_name: "Casey", last_name: "Colleague")

      patch portal_application_path, params: company_params(first_name: "Alex", last_name: "Sample", id: colleague.id, email: colleague.email)

      expect(colleague.reload).to have_attributes(first_name: "Casey", last_name: "Colleague")
      expect(applicant_user.reload).to have_attributes(first_name: "Alex", last_name: "Sample")
    end

    it "does not touch the user's email or password" do
      user = create(:applicant_user, first_name: "Alex")
      create(:onboarding_application, applicant: user.applicant)
      sign_in user, scope: :applicant_user
      before = user.slice(:email, :encrypted_password)

      patch portal_application_path, params: company_params(first_name: "Sam", email: "other@example.com", password: "changed-password-1!")

      expect(user.reload.slice(:email, :encrypted_password)).to eq(before)
    end
  end

  describe "a name that is too long" do
    let(:too_long) { "a" * 101 }

    it "re-renders the step with the error and the typed values, and saves nothing" do
      patch portal_application_path, params: company_params(first_name: too_long, last_name: "Sample")

      expect(response).to have_http_status(:unprocessable_content)
      expect(page).to have_css(".form-error", text: "too long")
      expect(page).to have_field("applicant_user[first_name]", with: too_long)
      expect(page).to have_field("applicant_user[last_name]", with: "Sample")
      expect(application.reload.current_step).to eq("company")
      expect(application.applicant.reload.company_number).not_to eq("12345678")
      expect(application.business_model_description).not_to eq("A specimen business model")
      expect(applicant_user.reload).to have_attributes(first_name: nil, last_name: nil)
    end
  end

  describe "a company save that fails" do
    it "keeps the typed names in the form and saves no name" do
      params = company_params(first_name: "Alex", last_name: "Sample")
      params[:onboarding_application][:business_model_description] = ""

      patch portal_application_path, params: params

      expect(response).to have_http_status(:unprocessable_content)
      expect(page).to have_field("applicant_user[first_name]", with: "Alex")
      expect(page).to have_field("applicant_user[last_name]", with: "Sample")
      expect(applicant_user.reload).to have_attributes(first_name: nil, last_name: nil)
    end
  end

  it "keeps names out of what is sent to the language model" do
    expect(OnboardingApplications::Snapshot::LLM_FACT_KEYS.map(&:to_s).grep(/name/)).to all(satisfy { |key| key.start_with?("company") })
    expect(OnboardingApplications::Snapshot::LLM_FACT_KEYS).not_to include(:first_name, :last_name, :name)
  end
end
