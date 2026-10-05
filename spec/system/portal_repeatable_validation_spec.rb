# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portal validation on repeatable and conditional fields", type: :system do
  let(:applicant_user) { create(:applicant_user) }

  before do
    create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "principals",
      completed_steps: %w[company fulfilment currencies processing payments descriptor pricing volumes countries]
    )
    sign_in_to_portal(applicant_user)
    visit portal_application_path(step: "principals")
  end

  it "shows inline errors instead of the native validation bubble on a repeatable row" do
    click_button "Save and continue"

    expect(page).to have_current_path(portal_application_path(step: "principals"))
    expect(page).to have_css("p.form-error", text: "Full name is required")
    expect(page).to have_css("input[name$='[name]'][aria-invalid='true']")
    expect(page.evaluate_script("document.querySelector('form[action]').noValidate")).to be(true)
    expect(page.find("[data-repeatable-fields-target='status']", visible: :all).text(:all)).to eq("3 fields need attention")
  end

  it "validates a dynamically added row and focuses its first invalid field" do
    fill_in_row(page.all("[data-repeatable-fields-target='item']").first, name: "Test Applicant", email: "applicant@example.com")
    click_button "Add director or beneficial owner"
    click_button "Save and continue"

    new_row = page.all("[data-repeatable-fields-target='item']").last
    expect(new_row).to have_css("p.form-error", text: "Full name is required")
    expect(page.evaluate_script("document.activeElement.name")).to eq(new_row.find("input[name$='[name]']")[:name])
    describedby = new_row.find("input[name$='[name]']")[:"aria-describedby"]
    expect(page).to have_css("##{describedby}", text: "Full name is required")
  end

  it "drops error state when an invalid row is removed" do
    fill_in_row(page.all("[data-repeatable-fields-target='item']").first, name: "Test Applicant", email: "applicant@example.com")
    click_button "Add director or beneficial owner"
    click_button "Save and continue"
    expect(page).to have_css("p.form-error")

    within(page.all("[data-repeatable-fields-target='item']").last) { click_button "Remove person" }

    expect(page).to have_no_css("p.form-error")
    expect(page).to have_no_css("[aria-invalid='true']")
    expect(page).to have_no_css("[aria-describedby]")
  end

  it "clears an error once the field is corrected" do
    click_button "Save and continue"
    expect(page).to have_css("p.form-error", text: "Full name is required")

    fill_in "Full name", with: "Test Applicant"
    find("input[name$='[email]']").click

    expect(page).to have_no_css("p.form-error", text: "Full name is required")
  end

  it "validates the ownership percentage when the role is switched after a failed submit" do
    click_button "Save and continue"
    expect(page).to have_css("p.form-error")

    row = page.first("[data-repeatable-fields-target='item']")
    fill_in_row(row, name: "Test Applicant", email: "applicant@example.com")
    select "Shareholder", from: "Role"
    click_button "Save and continue"

    expect(row).to have_css("p.form-error", text: /percentage is required/i)
  end

  it "renders a server-only failure through the same inline error component" do
    fill_in_row(page.first("[data-repeatable-fields-target='item']"), name: "   ", email: "applicant@example.com")
    click_button "Save and continue"

    row = page.first("[data-repeatable-fields-target='item']")
    expect(row).to have_css("p.form-error", text: "can't be blank")
    expect(row).to have_css("p.form-error", count: 1)
  end

  def fill_in_row(row, name:, email:)
    within(row) do
      find("input[name$='[name]']").set(name)
      find("input[name$='[date_of_birth]']").set(Date.new(1980, 1, 1))
      find("input[name$='[email]']").set(email)
    end
  end

  def sign_in_to_portal(user)
    visit new_applicant_user_session_path
    fill_in "applicant_user_email", with: user.email
    fill_in "applicant_user_password", with: user.password
    click_button "Sign in"
  end
end
