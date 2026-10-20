# frozen_string_literal: true

require "rails_helper"

# MH-408: the optional "set a password" prompt, in a real browser. The applicant
# signs in with the emailed code, as someone without a password would.
RSpec.describe "Optional password prompt", type: :system do
  let!(:user) { create(:applicant_user, :nameless, email: "applicant@example.com") }

  before do
    create(:onboarding_application, applicant: user.applicant, current_step: "fulfilment", completed_steps: [ "company" ])
    allow(ApplicantSignInCode).to receive(:generate_code).and_return("123456")
    ActionMailer::Base.deliveries.clear
  end

  def sign_in_with_code
    visit new_applicant_user_session_path
    fill_in "Email address", with: user.email
    click_button "Send me a code"
    expect(page).to have_text("Check your email")
    "123456".each_char { |digit| page.driver.browser.keyboard.type(digit) }
    click_button "Verify and continue"
    expect(page).to have_current_path(portal_root_path)
  end

  it "removes the banner on Not now without reloading the page, and keeps it away" do
    sign_in_with_code
    page.execute_script("window.__stillHere = true")
    expect(page).to have_css("#password-prompt", text: "Sign in faster next time")

    click_button "Not now"

    expect(page).to have_no_css("#password-prompt")
    expect(page.evaluate_script("window.__stillHere")).to be(true)
    expect(user.reload.password_prompt_dismissed_at).to be_present
    visit portal_root_path
    expect(page).to have_no_css("#password-prompt")
    expect(page).to have_button("Set a password")
  end

  it "emails the link and shows Check your email in the banner's place" do
    sign_in_with_code

    within("#password-prompt") { click_button "Set a password" }

    expect(page).to have_css("#password-prompt", text: "Check your email")
    expect(page).to have_text("We've sent a link to applicant@example.com")
    expect(ActionMailer::Base.deliveries.last.to).to eq([ "applicant@example.com" ])
  end

  it "lets a signed-in applicant follow the link and set a password" do
    sign_in_with_code
    token = user.send_reset_password_instructions

    visit edit_applicant_user_password_path(reset_password_token: token)
    expect(page).to have_css("h1", text: "Set a password")
    fill_in "New password", with: "a-new-password-1"
    fill_in "Confirm new password", with: "a-new-password-1"
    click_button "Save password"

    expect(page).to have_current_path(portal_root_path)
    expect(user.reload.valid_password?("a-new-password-1")).to be(true)
    expect(page).to have_no_css("#password-prompt")
    expect(page).to have_button("Change password")
  end

  it "fits a 375px screen with no sideways scrolling" do
    page.driver.resize(375, 812)
    sign_in_with_code

    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    expect(page).to have_css("#password-prompt")
  end
end
