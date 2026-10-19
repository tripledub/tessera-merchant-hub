# frozen_string_literal: true

require "rails_helper"

# MH-401: an applicant whose browser has dark mode saved still gets the light UI,
# while the admin side keeps honouring the saved preference.
RSpec.describe "Applicant portal is light only", type: :system do
  let(:applicant_user) { create(:applicant_user) }

  def save_dark_preference
    page.execute_script("localStorage.setItem('darkMode', 'true')")
  end

  def html_classes
    page.evaluate_script("document.documentElement.className")
  end

  def body_background
    page.evaluate_script("getComputedStyle(document.body).backgroundColor")
  end

  it "shows the light applicant sign-in page even with dark mode saved" do
    visit new_applicant_user_session_path
    save_dark_preference
    visit new_applicant_user_session_path

    expect(page).to have_css("form")
    expect(html_classes).not_to include("dark")
    expect(body_background).to eq("rgb(247, 249, 252)")
  end

  it "keeps the signed-in portal light with dark mode saved" do
    visit new_applicant_user_session_path
    save_dark_preference
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_root_path

    expect(page).to have_css("header")
    expect(html_classes).not_to include("dark")
    expect(body_background).to eq("rgb(247, 249, 252)")
  end

  it "still applies the saved dark preference on the admin side" do
    visit new_user_session_path
    save_dark_preference
    visit new_user_session_path

    expect(page).to have_css("form")
    expect(html_classes).to include("dark")
  end
end
