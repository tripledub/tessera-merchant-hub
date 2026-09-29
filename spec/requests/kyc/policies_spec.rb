# frozen_string_literal: true

require "rails_helper"

RSpec.describe "KYC policy catalogue", type: :request do
  before do
    Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
  end

  it "shows the effective policies and their coverage boundary to a PSP admin" do
    sign_in create(:user, :psp_admin)

    get kyc_policies_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "General", "Crypto exchange", "Gambling", "Forex brokerage", "Proprietary trading"
    )
    expect(response.body).to include("Shared requirement", "Sector-specific requirement")
    expect(response.body).to include("Passport validity", "Gaming licence", "Trading track record")
    expect(response.body).to include("Receipt does not mean approval")
    expect(response.body).not_to include("gambling.gaming_licence")
  end

  it "allows PSP support to view the catalogue" do
    sign_in create(:user, :psp_support)

    get kyc_policies_path

    expect(response).to have_http_status(:ok)
  end

  it "forbids merchant users" do
    sign_in create(:user, :merchant_admin)

    get kyc_policies_path

    expect(response).to have_http_status(:forbidden)
  end

  it "links the catalogue from the PSP KYC navigation" do
    sign_in create(:user, :psp_support)

    get applicants_path

    expect(response.body).to include(%(href="#{kyc_policies_path}"), ">Policies<")
  end

  it "does not expose the catalogue in merchant navigation" do
    sign_in create(:user, :merchant_admin)

    get shops_path

    expect(response.body).not_to include(%(href="#{kyc_policies_path}"))
  end
end
