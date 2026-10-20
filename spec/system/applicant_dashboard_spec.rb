# frozen_string_literal: true

require "rails_helper"

# MH-397: the dashboard's three states in a real browser, at phone and desktop widths.
RSpec.describe "Applicant dashboard", type: :system do
  let!(:user) { create(:applicant_user, :nameless, email: "applicant@example.com") }

  before { allow(ApplicantSignInCode).to receive(:generate_code).and_return("123456") }

  def sign_in_with_code
    visit new_applicant_user_session_path
    fill_in "Email address", with: user.email
    click_button "Send me a code"
    expect(page).to have_text("Check your email")
    "123456".each_char { |digit| page.driver.browser.keyboard.type(digit) }
    click_button "Verify and continue"
    expect(page).to have_current_path(portal_root_path)
  end

  def no_sideways_scroll?
    page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end

  def height_of(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  def states
    {
      "not started" => -> { },
      "in progress" => lambda {
        create(:onboarding_application, applicant: user.applicant, current_step: "fulfilment", completed_steps: [ "company" ])
      },
      "submitted" => lambda {
        create(:onboarding_application, applicant: user.applicant, status: :submitted, current_step: "review",
               completed_steps: OnboardingApplication::STEPS)
      }
    }
  end

  [ 375, 1280 ].each do |width|
    %w[not\ started in\ progress submitted].each do |state|
      it "renders the #{state} state at #{width}px with no sideways scrolling" do
        page.driver.resize(width, 900)
        states.fetch(state).call
        sign_in_with_code

        expect(page).to have_css("h1")
        expect(no_sideways_scroll?).to be(true)
        expect(page).to have_css(".kyn-card")
      end
    end
  end

  it "keeps the main buttons at least 44px tall, and the content column narrow on desktop" do
    page.driver.resize(1280, 900)
    states.fetch("in progress").call
    sign_in_with_code

    expect(height_of("a[href='#{portal_onboarding_path}']")).to be >= 44
    expect(height_of("a[href='#{portal_application_path}']")).to be >= 44
    expect(page.evaluate_script("document.querySelector('.kyn-card').getBoundingClientRect().width")).to be <= 720
  end

  it "fills the bar to the percentage it states" do
    states.fetch("in progress").call
    sign_in_with_code

    percent = find("[role='progressbar']")["aria-valuenow"].to_i
    fill_width = page.evaluate_script("document.querySelector('.kyn-progress-fill').getBoundingClientRect().width")
    track_width = page.evaluate_script("document.querySelector('.kyn-progress').getBoundingClientRect().width")

    expect(fill_width / track_width * 100).to be_within(1.5).of(percent)
  end
end
