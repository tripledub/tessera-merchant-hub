# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portal application shell", type: :request do
  it "requires applicant authentication" do
    get portal_application_path

    expect(response).to redirect_to(new_applicant_user_session_path)
  end

  it "creates a draft application for the authenticated applicant" do
    applicant_user = create(:applicant_user)
    sign_in applicant_user, scope: :applicant_user

    expect { get portal_application_path }.to change(OnboardingApplication, :count).by(1)

    application = OnboardingApplication.last
    expect(application).to have_attributes(applicant: applicant_user.applicant, status: "draft")
    expect(response.body).to include("Company details", "Review and submit")
    page = Capybara.string(response.body)
    expect(page).to have_link("Company details")
    expect(page).to have_no_link("Review and submit")
  end

  it "saves progress and resumes it after logout and login" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: company_details_params(application)
    expect(response).to redirect_to(portal_application_path(step: "fulfilment"))

    delete destroy_applicant_user_session_path
    sign_in applicant_user, scope: :applicant_user
    get portal_application_path

    expect(response).to redirect_to(portal_application_path(step: "fulfilment"))
    expect(application.reload.completed_steps).to eq([ "company" ])
  end

  it "renders the company fields with previously saved shared-domain values" do
    applicant_user = create(:applicant_user)
    application = create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      business_model_description: "Existing business description",
      operating_licence: "None required"
    )
    create(:applicant_domain, applicant: applicant_user.applicant, name: "existing.example")
    create(:address, :business, :primary, addressable: applicant_user.applicant, line1: "1 Existing Street")
    create(:address, :primary, addressable: applicant_user.applicant, type: "Address::Trading", line1: "2 Trading Road")
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "company")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      application.applicant.company_name,
      "Existing business description",
      "existing.example",
      "1 Existing Street",
      "2 Trading Road"
    )
  end

  it "returns validation errors against the company step without persisting partial answers" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user
    params = company_details_params(application)
    params[:onboarding_application][:business_model_description] = ""

    patch portal_application_path, params: params

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Business model description can&#39;t be blank")
    expect(application.reload.current_step).to eq("company")
  end

  it "shows a website validation error against the affected repeated item" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user
    params = company_details_params(application)
    params[:onboarding_application][:applicant_attributes][:applicant_domains_attributes]["0"][:name] = "not a domain"

    patch portal_application_path, params: params

    expect(response).to have_http_status(:unprocessable_content)
    website_item = Capybara.string(response.body).find("[data-repeatable-fields-target='item']")
    expect(website_item).to have_field(with: "not a domain")
    expect(website_item).to have_css(".form-error", text: "Name is invalid")
  end

  it "lets an applicant revisit a completed step without changing saved progress" do
    applicant_user = create(:applicant_user)
    application = create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "processing",
      completed_steps: %w[company fulfilment currencies]
    )
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "company")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Company details")
    expect(application.reload.current_step).to eq("processing")
  end

  it "redirects attempts to visit a future step back to the current step" do
    applicant_user = create(:applicant_user)
    create(:onboarding_application, applicant: applicant_user.applicant, current_step: "company")
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "review")

    expect(response).to redirect_to(portal_application_path(step: "company"))
  end

  it "does not expose another applicant's application through an identifier" do
    applicant_user = create(:applicant_user)
    other_application = create(:onboarding_application)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(id: other_application.id)

    own_application = applicant_user.applicant.reload.onboarding_application
    expect(response).to have_http_status(:ok)
    expect(own_application).to be_present
    expect(response.body).not_to include(other_application.id)
  end

  it "returns not found for an unknown step" do
    applicant_user = create(:applicant_user)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "unknown")

    expect(response).to have_http_status(:not_found)
  end

  def company_details_params(application)
    applicant = application.applicant
    {
      step: "company",
      onboarding_application: {
        business_model_description: "A specimen business model",
        operating_licence: "None required",
        applicant_attributes: {
          id: applicant.id,
          company_name: applicant.company_name,
          company_number: "12345678",
          sector: applicant.sector,
          primary_business_address_attributes: {
            line1: "1 Test Street", city: "Testford", postcode: "TE1 1ST", country: "United Kingdom"
          },
          trading_address_attributes: {
            line1: "2 Example Road", city: "Testford", postcode: "TE1 2ST", country: "United Kingdom"
          },
          applicant_domains_attributes: { "0" => { name: "specimen.example" } }
        }
      }
    }
  end
end
