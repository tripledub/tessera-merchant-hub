# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portal target countries picker", type: :system do
  let(:applicant_user) { create(:applicant_user) }
  let!(:application) do
    create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "countries",
      completed_steps: %w[company fulfilment currencies processing payments descriptor volumes]
    )
  end

  before do
    visit new_applicant_user_session_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_application_path(step: "countries")
  end

  it "searches, selects countries as pills, removes one and saves the rest" do
    expect(page).to have_no_css("#country-picker-select", visible: :visible)

    search = find_field("Search countries")
    search.fill_in with: "kingd"
    expect(page).to have_css("[role='option']", count: 1, text: "United Kingdom")
    find("[role='option']", text: "United Kingdom").click

    search.fill_in with: "zeal"
    find("[role='option']", text: "New Zealand").click

    expect(page).to have_css("[data-country-pill]", count: 2)
    expect(page).to have_css("[data-country-pill='GB']", text: "United Kingdom")

    find("button[aria-label='Remove New Zealand']").click
    expect(page).to have_css("[data-country-pill]", count: 1)

    click_button "Save and continue"

    expect(page).to have_current_path(portal_application_path(step: "principals"))
    expect(application.reload.onboarding_countries.pluck(:code)).to eq([ "GB" ])
  end

  it "finds accented country names without typing the accent" do
    find_field("Search countries").fill_in with: "reunion"

    expect(page).to have_css("[role='option']", text: "Réunion")
  end

  it "supports the keyboard and shows an empty state" do
    search = find_field("Search countries")
    search.fill_in with: "zzzz"
    expect(page).to have_css("li", text: "No countries found")

    search.fill_in with: "ireland"
    search.send_keys(:down, :enter)
    expect(page).to have_css("[data-country-pill='IE']")
    expect(page).to have_current_path(portal_application_path(step: "countries"))

    search.send_keys(:backspace)
    expect(page).to have_no_css("[data-country-pill]")
  end

  it "restores saved countries as pills and blocks an empty submission" do
    application.onboarding_countries.create!(code: "FR")
    visit portal_application_path(step: "countries")

    expect(page).to have_css("[data-country-pill='FR']", text: "France")
    find("button[aria-label='Remove France']").click
    click_button "Save and continue"

    expect(page).to have_content("Target countries can't be blank")
    expect(application.reload.current_step).to eq("countries")
  end
end
