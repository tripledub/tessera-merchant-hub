# frozen_string_literal: true

require "rails_helper"

# MH-425: the principals step and the review page in the applicant look.
RSpec.describe "Portal application form: principals and review", type: :system do
  let!(:applicant_user) { create(:applicant_user) }

  def sign_in_and_open(step, **attributes)
    completed = OnboardingApplication::STEPS.take_while { |candidate| candidate != step }
    create(:onboarding_application, applicant: applicant_user.applicant, current_step: step, completed_steps: completed,
                                    **attributes)
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

      it "keeps the principals fields tappable and the role question revealing the ownership percentage" do
        sign_in_and_open("principals")

        expect(visible_heights("form input.kyn-input, form select.kyn-input").min).to be >= 44
        expect(page).to have_no_field("Ownership or share percentage", visible: :visible)
        select "PSC", from: "Role"
        expect(page).to have_field("Ownership or share percentage", visible: :visible)
        expect(no_horizontal_scroll?).to be(true)
      end

      it "adds another principal with the secondary button" do
        sign_in_and_open("principals")

        click_button "Add director or beneficial owner"

        expect(page).to have_css("[data-repeatable-fields-target='item']", count: 2)
        expect(no_horizontal_scroll?).to be(true)
      end

      it "shows an invalid email in the applicant look" do
        sign_in_and_open("principals")

        fill_in "Email address", with: "not-an-email"
        find_field("Email address").send_keys(:tab)

        expect(page).to have_css("input.kyn-input[aria-invalid='true']")
        expect(page).to have_css(".kyn-field .form-error")
      end

      it "shows the review cards with red missing rows, links to fix them and 44px Edit links" do
        sign_in_and_open("review")

        expect(page).to have_css("[data-testid='review-missing']", minimum: 1)
        expect(page).to have_css("[data-testid='review-missing'].text-kyn-error a", text: "Add this before you submit.", minimum: 1)
        expect(visible_heights("main a.kyn-link").min).to be >= 44
        expect(no_horizontal_scroll?).to be(true)
      end

      it "takes the applicant to the right step from a missing row" do
        sign_in_and_open("review")

        within(first("[data-testid='review-missing']")) { click_link "Add this before you submit." }

        expect(page).to have_current_path(/step=/)
        expect(page).to have_css("form")
      end
    end
  end

  it "sizes the submit button to 240px on desktop and full width on a phone" do
    page.driver.resize(1280, 900)
    sign_in_and_open("review")
    desktop = page.evaluate_script("document.querySelector('form input[type=submit]').getBoundingClientRect().width")
    page.driver.resize(390, 844)
    visit portal_application_path(step: "review")
    phone = page.evaluate_script("document.querySelector('form input[type=submit]').getBoundingClientRect().width")

    expect(desktop).to eq(240)
    expect(phone).to be > 300
  end
end
