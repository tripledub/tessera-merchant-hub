# frozen_string_literal: true

require "rails_helper"

# MH-415: a business added by the PSP is asked to confirm the name the PSP gave,
# not to type it again.
RSpec.describe "Chat opening: confirming the company name", type: :system do
  let(:applicant) { create(:applicant, name: "Stew & Co", company_name: nil, company_number: nil) }
  let!(:applicant_user) { create(:applicant_user, applicant: applicant) }

  def sign_in_and_open_chat
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_onboarding_path
  end

  it "offers the PSP's name on the button, and carries on without asking for it" do
    sign_in_and_open_chat

    expect(page).to have_text("I have your company as Stew & Co. Is this correct?")
    expect(page).to have_button("No, a different name")

    click_button "Yes, Stew & Co"

    expect(page).to have_text("To finish your company details I still need")
    expect(page).to have_no_text("tell us the name of your business")
    expect(applicant.reload.company_name).to eq("Stew & Co")
  end

  it "asks for the name when the applicant says it is a different one" do
    sign_in_and_open_chat

    click_button "No, a different name"

    expect(page).to have_text("Please tell us the name of your business")
    expect(applicant.reload.company_name).to be_nil
  end

  it "keeps a long company name on the button inside a phone screen" do
    applicant.update!(name: "Evergreen Wholesale Distribution and Logistics Holdings Limited")
    page.driver.resize(375, 812)
    sign_in_and_open_chat

    expect(page).to have_button("Yes, Evergreen Wholesale Distribution and Logistics Holdings Limited")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  end
end
