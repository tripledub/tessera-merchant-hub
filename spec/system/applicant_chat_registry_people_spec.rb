# frozen_string_literal: true

require "rails_helper"

# MH-417: the registry's people are offered one at a time, with Yes/No buttons.
RSpec.describe "Chat: confirming the registry's people", type: :system do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets", registry_jurisdiction: "gb") }
  let!(:applicant_user) { create(:applicant_user, applicant: applicant) }
  let(:profile) { create(:registry_profile, applicant: applicant, company_name: "ACME WIDGETS LIMITED") }
  let(:onboarding_session) do
    create(:onboarding_session, applicant: applicant, current_stage: :directors_ubos,
                                stage_data: { "company_info" => { "company_name" => "Acme Widgets" },
                                              "registry_check" => { "state" => "confirmed", "profile_id" => profile.id } })
  end

  before do
    create(:registry_director, registry_profile: profile, name: "DOE, Jane")
    create(:registry_person_with_significant_control, registry_profile: profile, name: "Mr Albert Edward Short")
    create(:onboarding_message, onboarding_session: onboarding_session, role: :bot,
                                content: Onboarding::RegistryPeople.begin!(onboarding_session))
  end

  def sign_in_and_open_chat
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_onboarding_path
  end

  it "asks for the missing details on Yes, and offers the next person on No" do
    sign_in_and_open_chat

    expect(page).to have_text("The registry lists Jane Doe as a director")
    click_button "Yes, that's them"
    expect(page).to have_text("What are Jane Doe's date of birth and nationality?")
    expect(page).to have_no_button("Yes, that's them")
  end

  it "records a dispute on No and moves to the next person" do
    sign_in_and_open_chat

    click_button "No, not involved"

    expect(page).to have_text("The registry lists Albert Edward Short as a person with significant control")
    expect(applicant.data_conflicts.status_open.where(field: "involvement").count).to eq(1)
  end

  it "keeps the buttons inside a phone screen" do
    page.driver.resize(375, 812)
    sign_in_and_open_chat

    expect(page).to have_button("No, not involved")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    heights = page.evaluate_script(
      "Array.from(document.querySelectorAll('[data-testid=registry-person] button')).map(b => b.getBoundingClientRect().height)"
    )
    expect(heights.min).to be >= 44
  end
end
