# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Staff self-service application review", type: :request do
  it "links the application status and submission date from the applicant workspace" do
    user = create(:user, :psp_admin)
    applicant = create(:applicant)
    application = create(:onboarding_application, applicant: applicant, status: :submitted,
      submitted_at: Time.zone.parse("2026-09-29 10:30"))
    sign_in user

    get applicant_path(applicant)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Self-service application: Submitted", "Review applicant-supplied information")
    expect(response.body).to include(applicant_onboarding_application_path(applicant))
    expect(response.body).to include(I18n.l(application.submitted_at, format: :long))
  end

  it "shows applicant-supplied data from the canonical onboarding records" do
    user = create(:user, :psp_support)
    applicant = create(:applicant, company_number: "12345678")
    application = create(:onboarding_application, applicant: applicant,
      business_model_description: "Applicant supplied model", descriptor: "SPECIMEN")
    application.onboarding_countries.create!(code: "DE")
    create(:kyc_principal, applicant: applicant, name: "Applicant Owner", source: :applicant_declared,
      date_of_birth: Date.new(1980, 1, 2), email: "owner@example.com")
    sign_in user

    get applicant_onboarding_application_path(applicant)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Applicant supplied model", "SPECIMEN", "Germany", "Applicant Owner", "supplied by the applicant"
    )
    expect(application.reload).to be_draft
  end

  it "shows shared onboarding requirements after submission" do
    user = create(:user, :psp_admin)
    applicant = create(:applicant, sector: :crypto_exchange)
    create(:onboarding_application, applicant: applicant, status: :submitted)
    sign_in user

    get applicant_onboarding_application_path(applicant)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Onboarding requirements", "Missing information", "Missing documents",
      "Vasp registration", "Wallet custody infrastructure attestation"
    )
  end

  it "does not evaluate requirements for a draft application" do
    user = create(:user, :psp_admin)
    applicant = create(:applicant)
    create(:onboarding_application, applicant: applicant, status: :draft)
    sign_in user

    get applicant_onboarding_application_path(applicant)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Onboarding requirements")
  end

  it "returns not found when an applicant has no self-service application" do
    user = create(:user, :psp_admin)
    applicant = create(:applicant)
    sign_in user

    get applicant_onboarding_application_path(applicant)

    expect(response).to have_http_status(:not_found)
  end

  it "does not allow merchant staff to review an applicant application" do
    user = create(:user, :merchant_admin)
    applicant = create(:applicant)
    create(:onboarding_application, applicant: applicant)
    sign_in user

    get applicant_onboarding_application_path(applicant)

    expect(response).to have_http_status(:forbidden)
  end
end
