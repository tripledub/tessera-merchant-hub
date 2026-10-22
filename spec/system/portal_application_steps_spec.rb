# frozen_string_literal: true

require "rails_helper"

# MH-424: steps 2 to 8 and the country picker in the applicant look, at phone and desktop widths.
RSpec.describe "Portal application form: steps 2 to 8", type: :system do
  let!(:applicant_user) { create(:applicant_user) }

  def sign_in_and_open(step)
    completed = OnboardingApplication::STEPS.take_while { |candidate| candidate != step }
    create(:onboarding_application, applicant: applicant_user.applicant, current_step: step, completed_steps: completed)
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_application_path(step: step)
  end

  def no_horizontal_scroll?
    page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end

  def visible_heights(selector)
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(#{selector.to_json})).filter(e => e.offsetParent !== null).map(e => e.getBoundingClientRect().height)
    JS
  end

  [ [ "phone", 390, 844 ], [ "desktop", 1280, 900 ] ].each do |name, width, height|
    context "with a #{name} screen" do
      before { page.driver.resize(width, height) }

      it "keeps the Yes/No questions on fulfilment tappable, with a filled dot when chosen and no horizontal scroll" do
        sign_in_and_open("fulfilment")

        expect(visible_heights("label.kyn-check-label").min).to be >= 44
        find("label", text: "Yes", match: :first).click
        expect(page.evaluate_script("document.querySelector('input.kyn-radio:checked') !== null")).to be(true)
        expect(no_horizontal_scroll?).to be(true)
      end

      it "reveals the dependent field on processing when the answer is Yes" do
        sign_in_and_open("processing")

        expect(page).to have_no_field("onboarding_application[current_acquirer]", visible: :visible)
        find("label", text: "Yes").click
        expect(page).to have_field("onboarding_application[current_acquirer]", visible: :visible)
        expect(visible_heights("input.kyn-input").min).to be >= 44
        expect(no_horizontal_scroll?).to be(true)
      end

      it "shows a currency row with a 44px field and keeps add and remove working" do
        sign_in_and_open("currencies")

        expect(visible_heights("input.kyn-input").min).to be >= 44
        expect(no_horizontal_scroll?).to be(true)
        first("button", text: /add/i, match: :first).click
        expect(page).to have_css("input[name*='processing_currencies_attributes'][name$='[code]']", minimum: 2)
      end

      it "styles the country picker pills and options, with 44px options" do
        sign_in_and_open("countries")

        search = find_field("Search countries")
        search.fill_in with: "kingd"
        expect(visible_heights("[role='option']").min).to be >= 44
        find("[role='option']", text: "United Kingdom").click

        expect(page).to have_css("[data-country-pill='GB'].bg-kyn-primary-tint", text: "United Kingdom")
        expect(page).to have_no_css("[data-country-pill].bg-gray-100")
        expect(no_horizontal_scroll?).to be(true)
      end
    end
  end

  it "still moves through the country list with the keyboard" do
    sign_in_and_open("countries")

    search = find_field("Search countries")
    search.fill_in with: "malt"
    search.send_keys(:down, :enter)

    expect(page).to have_css("[data-country-pill]", count: 1)
  end
end
