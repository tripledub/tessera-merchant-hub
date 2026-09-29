# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portal company details: same as registered address", type: :system do
  it "advances past the company step with the checkbox left checked and trading fields blank" do
    applicant_user = create(:applicant_user)
    create(:onboarding_application, applicant: applicant_user.applicant)

    sign_in_to_portal(applicant_user)
    visit portal_application_path(step: "company")

    checkbox = find_field("onboarding_application[trading_address_same_as_registered]")
    expect(checkbox).to be_checked
    expect(find("[data-address-same-as-target='fields']", visible: :all)).not_to be_visible

    fill_in_company_details

    click_button "Save and continue"

    expect(page).to have_current_path(portal_application_path(step: "fulfilment"))
    applicant_user.applicant.reload
    expect(applicant_user.applicant.trading_address).to have_attributes(
      line1: "1 System Spec Street", city: "Systonville", country: "United Kingdom"
    )
    expect(applicant_user.applicant.addresses.count).to eq(2)
  end

  def sign_in_to_portal(applicant_user)
    visit new_applicant_user_session_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
  end

  def fill_in_company_details
    within "fieldset", text: "Registered address" do
      fill_in "Address line 1", with: "1 System Spec Street"
      fill_in "City", with: "Systonville"
      fill_in "Country", with: "United Kingdom"
    end
    fill_in "onboarding_application[applicant_attributes][company_name]", with: "System Spec Co"
    fill_in "onboarding_application[applicant_attributes][company_number]", with: "12345678"
    fill_in "onboarding_application[applicant_attributes][applicant_domains_attributes][0][name]", with: "systemspec.example"
    fill_in "onboarding_application[business_model_description]", with: "Testing the same-as-registered checkbox"
    fill_in "onboarding_application[operating_licence]", with: "None required"
  end
end
