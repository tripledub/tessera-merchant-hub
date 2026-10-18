# frozen_string_literal: true

require "rails_helper"

# MH-396: the shared password field and the remember-me row on the Kynetic
# sign-in page, in a real browser.
RSpec.describe "Applicant sign in", type: :system do
  before { visit new_applicant_user_session_path }

  def height(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  describe "the password show/hide toggle" do
    it "is a labelled 44px control that reports its state" do
      toggle = page.find("button[data-action='password-toggle#toggle']")

      expect(toggle["aria-label"]).to eq("Show password")
      expect(toggle["aria-pressed"]).to eq("false")
      expect(height("button[data-action='password-toggle#toggle']")).to be >= 44
      expect(page).to have_field("Password", type: "password")

      toggle.click

      expect(page).to have_field("Password", type: "text")
      expect(toggle["aria-label"]).to eq("Hide password")
      expect(toggle["aria-pressed"]).to eq("true")

      toggle.click

      expect(page).to have_field("Password", type: "password")
      expect(toggle["aria-label"]).to eq("Show password")
      expect(toggle["aria-pressed"]).to eq("false")
    end
  end

  describe "the remember-me row" do
    it "toggles from its label and is a 44px target" do
      expect(height("label.kyn-check-label")).to be >= 44
      expect(page).to have_unchecked_field("Remember me", visible: :all)

      page.find("label.kyn-check-label").click

      expect(page).to have_checked_field("Remember me", visible: :all)
    end
  end

  describe "the whole card" do
    it "fits a 375px screen with no sideways scrolling" do
      page.driver.resize(375, 812)
      visit new_applicant_user_session_path

      expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
      expect(page).to have_css(".kyn-card")
    end
  end
end
