# frozen_string_literal: true

require "rails_helper"

# MH-406: the Welcome back page and the code flow for a returning applicant, in a real browser.
RSpec.describe "Returning applicant sign-in", type: :system do
  let!(:user) { create(:applicant_user, :nameless, email: "returning@example.com") }

  before { allow(ApplicantSignInCode).to receive(:generate_code).and_return("123456") }

  def request_code_for(address)
    visit new_applicant_user_session_path
    fill_in "Email address", with: address
    click_button "Send me a code"
    expect(page).to have_text("Check your email")
  end

  def type_code(digits)
    digits.each_char { |digit| page.driver.browser.keyboard.type(digit) }
  end

  it "signs a returning applicant in with the emailed code" do
    request_code_for(user.email)
    expect(page).to have_text("If that address is registered, we've sent a 6-digit code to #{user.email}")

    type_code("123456")
    click_button "Verify and continue"

    expect(page).to have_current_path(portal_root_path)
  end

  it "shows the same page for an address with no account, which can never sign in" do
    request_code_for("nobody@example.com")
    expect(page).to have_text("If that address is registered, we've sent a 6-digit code to nobody@example.com")

    type_code("123456")
    click_button "Verify and continue"

    expect(page).to have_css("[role='alert']", text: "That code isn't right. You have 4 attempts left.")
    expect(page).to have_current_path(portal_sign_in_code_path)
  end

  it "offers the password form, and a way back to the code page" do
    visit new_applicant_user_session_path
    click_link "Use a password instead"

    expect(page).to have_current_path(applicant_user_password_sign_in_path)
    expect(page).to have_field("Password", type: "password")

    click_link "Email me a code instead"
    expect(page).to have_text("Welcome back")
  end

  it "keeps the password form after a wrong password" do
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: user.email
    fill_in "applicant_user_password", with: "wrong-password"
    click_button "Sign in"

    expect(page).to have_field("Password", type: "password")
    expect(page).to have_no_button("Send me a code")
  end

  it "fits a 375px screen with no sideways scrolling" do
    page.driver.resize(375, 812)
    visit new_applicant_user_session_path

    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    expect(page).to have_button("Send me a code")
  end
end
