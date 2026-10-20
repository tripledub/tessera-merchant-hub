# frozen_string_literal: true

require "rails_helper"

# MH-391: the chat opens with the company type and country as chips, then looks
# the company up by its number and asks the applicant to confirm it.
RSpec.describe "Chat opening: registry first", type: :system do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets", company_number: nil, registry_jurisdiction: "gb") }
  let!(:applicant_user) { create(:applicant_user, applicant: applicant) }
  let(:onboarding_session) { create(:onboarding_session, applicant: applicant, current_stage: :company_info) }

  def sign_in_and_open_chat
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_onboarding_path
  end

  it "offers the company types as chips, each at least 44px tall, and sends the label as the reply" do
    onboarding_session.update!(stage_data: { "company_info" => { "company_name" => "Acme Widgets" } })
    create(:onboarding_message, onboarding_session: onboarding_session, role: :bot, content: "What type of company is it?")
    sign_in_and_open_chat

    expect(page).to have_css("#onboarding_quick_replies button", count: 6)
    heights = page.evaluate_script(
      "Array.from(document.querySelectorAll('#onboarding_quick_replies button')).map(b => b.getBoundingClientRect().height)"
    )
    expect(heights.min).to be >= 44

    find("#onboarding_quick_replies button", text: "Sole trader", exact_text: true).click

    expect(page).to have_css(".kyn-bubble-applicant", text: "Sole trader")
  end

  context "when the registry has the company" do
    let(:profile) do
      create(:registry_profile, applicant: applicant, company_name: "ACME WIDGETS LIMITED", company_number: "12345678")
    end

    before do
      create(:registry_address, registry_profile: profile)
      onboarding_session.update!(stage_data: { "company_info" => {
        "company_name" => "Acme Widgets", "company_type" => "limited_company",
        "country_of_incorporation" => "United Kingdom", "registration_number" => "12345678"
      } })
      allow(Registry::Lookup).to receive(:call).and_return(Registry::Lookup::Result.success(profile))
      Onboarding::RegistryCompanyCheck.run!(onboarding_session)
      create(:onboarding_message, onboarding_session: onboarding_session, role: :bot,
                                  content: Onboarding::RegistryCompanyCheck.prompt(onboarding_session))
    end

    it "shows the match and, on Yes, saves it and moves on to the directors" do
      sign_in_and_open_chat

      expect(page).to have_text("I found ACME WIDGETS LIMITED, active, registered at 10 Business Park, Bristol, BS1 1AA")
      expect(page).to have_no_css("#onboarding_quick_replies .kyn-chip")

      click_button "Yes, that's it"

      expect(page).to have_text("Next, let’s add the directors and beneficial owners")
      expect(page).to have_no_button("Yes, that's it")
      expect(applicant.reload.company_name).to eq("ACME WIDGETS LIMITED")
    end

    it "keeps the buttons inside a phone screen" do
      page.driver.resize(375, 812)
      sign_in_and_open_chat

      expect(page).to have_button("No, not mine")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    end
  end
end
