# frozen_string_literal: true

require "rails_helper"

# MH-400: the form's frame at phone and desktop widths.
RSpec.describe "Portal application form: frame", type: :system do
  let!(:applicant_user) { create(:applicant_user) }

  before do
    create(:onboarding_application, applicant: applicant_user.applicant, current_step: "fulfilment",
                                    completed_steps: [ "company" ])
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
  end

  def no_horizontal_scroll?
    page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end

  def height_of(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  describe "on a phone" do
    before do
      page.driver.resize(390, 844)
      visit portal_application_path(step: "company")
    end

    it "starts the form below one compact bar, with the list closed" do
      expect(page).to have_css("details[data-testid='steps-bar']:not([open])")
      expect(page).to have_text("Step 1 of 10")
      expect(page).to have_text("All steps")
      expect(page).to have_no_text("Fulfilment and services")
      expect(page).to have_field("onboarding_application[applicant_attributes][company_name]")
      top = page.evaluate_script("document.querySelector('form').getBoundingClientRect().top")
      expect(top).to be < 420
    end

    it "opens the full list and closes it again, by touch or keyboard" do
      find("summary", text: "All steps").click

      expect(page).to have_text("Fulfilment and services")
      expect(page).to have_text("Hide steps")
      expect(page).to have_css("li[aria-disabled='true']", count: 8, visible: :visible)
      expect(page).to have_css("[aria-current='step']", text: "Company details")

      find("summary", text: "Hide steps").click
      expect(page).to have_no_text("Fulfilment and services")
    end

    it "keeps a 44px tap target on the bar and no horizontal scroll" do
      expect(height_of("details[data-testid='steps-bar'] summary")).to be >= 44
      expect(no_horizontal_scroll?).to be(true)
    end

    it "gives the fields and the button at least 44px" do
      heights = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("form input.kyn-input, form select.kyn-input, form input[type=submit]")).filter(e => e.offsetParent !== null).map(e => e.getBoundingClientRect().height)
      JS
      expect(heights.min).to be >= 44
    end

    it "shows the field error in the applicant look when a required field is left empty" do
      fill_in "onboarding_application[applicant_attributes][company_name]", with: ""
      find("body").click
      find_field("onboarding_application[applicant_attributes][company_name]").send_keys(:tab)

      expect(page).to have_css("input.kyn-input[aria-invalid='true']")
      expect(page).to have_css(".kyn-field .form-error", text: "required")
    end
  end

  describe "on desktop" do
    before do
      page.driver.resize(1280, 900)
      visit portal_application_path(step: "company")
    end

    it "shows the sidebar with the step states, not the phone bar" do
      expect(page).to have_no_css("details[data-testid='steps-bar']", visible: :visible)
      within("[data-testid='steps-sidebar']") do
        expect(page).to have_css("li", count: 10)
        expect(page).to have_css("[aria-current='step']", text: "Company details")
        expect(page).to have_css("li[aria-disabled='true']", count: 8)
        expect(page).to have_text("Finish a step to unlock the next one.")
      end
      expect(page).to have_css("h1", text: "Company details", visible: :visible, count: 1)
      expect(no_horizontal_scroll?).to be(true)
    end

    it "puts the form beside the sidebar and the name and number side by side" do
      sidebar_right = page.evaluate_script("document.querySelector(\"[data-testid='steps-sidebar']\").getBoundingClientRect().right")
      card_left = page.evaluate_script("document.querySelector('section.kyn-card').getBoundingClientRect().left")
      expect(card_left).to be > sidebar_right

      name_top = page.evaluate_script("document.getElementById('onboarding_application_applicant_attributes_company_name').getBoundingClientRect().top")
      number_top = page.evaluate_script("document.getElementById('onboarding_application_applicant_attributes_company_number').getBoundingClientRect().top")
      expect(name_top).to eq(number_top)
    end

    it "keeps the step links at least 44px tall and the continue button right-aligned at 240px" do
      expect(height_of("[data-testid='steps-sidebar'] li:first-child a")).to be >= 44
      width = page.evaluate_script("document.querySelector('form input[type=submit]').getBoundingClientRect().width")
      expect(width).to eq(240)
    end
  end
end
