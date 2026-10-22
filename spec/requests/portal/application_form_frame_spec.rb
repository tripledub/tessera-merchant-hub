# frozen_string_literal: true

require "rails_helper"

# MH-400: the long form's frame, step navigation and Company step in the Kynetic look.
RSpec.describe "Portal application form: frame and Company step", type: :request do
  let(:applicant_user) { create(:applicant_user) }

  # The restyled files must carry none of the old admin theme. Later restyle stories add theirs.
  RESTYLED_FILES = %w[
    app/views/portal/applications/show.html.erb
    app/views/portal/applications/_steps_list.html.erb
    app/views/portal/applications/_error_summary.html.erb
    app/views/portal/applications/_company_fields.html.erb
    app/views/portal/applications/_your_details_fields.html.erb
    app/views/portal/applications/_address_fields.html.erb
    app/views/portal/applications/_domain_fields.html.erb
    app/views/shared/repeatable_fields/_component.html.erb
    app/views/shared/repeatable_fields/_item.html.erb
  ].freeze
  ADMIN_THEME = /
    (?<![\w-])(?:card|form-input|form-input-error|form-label|form-select|btn-primary|btn-secondary)(?![\w-])
    | (?<![\w-])(?:bg|text|border|ring|from|to|via)-(?:brand|gray)-\d
    | \bdark:
  /x

  before do
    create(:onboarding_application, applicant: applicant_user.applicant, current_step: "fulfilment",
                                    completed_steps: [ "company" ])
    sign_in applicant_user, scope: :applicant_user
  end

  def page
    Capybara.string(response.body)
  end

  describe "the old admin theme" do
    RESTYLED_FILES.each do |path|
      it "is gone from #{path}" do
        expect(Rails.root.join(path).read).not_to match(ADMIN_THEME)
      end
    end

    it "is still used by the staff Devise views through the shared error partial (unchanged)" do
      expect(Rails.root.join("app/views/shared/_error_messages.html.erb").read).to include("dark:")
    end
  end

  describe "the step navigation" do
    before { get portal_application_path(step: "fulfilment") }

    it "titles the page with the current step and says which step it is" do
      expect(page).to have_css("h1", text: "Fulfilment and services")
      expect(page).to have_text("Step 2 of 10")
    end

    it "gives phones one compact bar that opens the full list (no JavaScript)" do
      bar = page.find("details[data-testid='steps-bar']")
      expect(bar).to have_css("summary", text: "Step 2 of 10")
      expect(bar).to have_css("summary", text: "All steps")
      expect(bar).to have_css("ol li", count: 10, visible: :all)
    end

    it "keeps the full list as a sidebar from lg up" do
      sidebar = page.find("[data-testid='steps-sidebar']")
      expect(sidebar).to have_css("ol li", count: 10, visible: :all)
      expect(sidebar[:class]).to include("hidden", "lg:block")
    end

    it "marks the current step, links the done and current steps, and locks the rest" do
      list = page.find("[data-testid='steps-sidebar'] ol")
      current = list.find("li[aria-current='step']")
      expect(current).to have_text("Fulfilment and services")
      expect(list).to have_css("a[href='#{portal_application_path(step: 'company')}']", text: "Company details")
      locked = list.all("li[aria-disabled='true']")
      expect(locked.size).to eq(8)
      expect(locked).to all(have_no_css("a", visible: :all))
    end

    it "shows the unlock footnote" do
      expect(page).to have_text("Finish a step to unlock the next one. Your answers are saved as you go.")
    end

    it "keeps the progress bar's value" do
      bar = page.find("[role='progressbar']")
      expect(bar["aria-valuenow"]).to eq("10")
    end
  end

  describe "the Company step" do
    before { get portal_application_path(step: "company") }

    it "uses the Kynetic fields, labels and button" do
      expect(page).to have_css("input.kyn-input[name='onboarding_application[applicant_attributes][company_name]']")
      expect(page).to have_css("label.kyn-label", text: "Company name")
      expect(page).to have_css("select.kyn-input")
      expect(page).to have_css("input[type='checkbox'].kyn-checkbox")
      expect(page).to have_css("input[type='submit'].kyn-btn-primary[value='Save and continue']")
    end

    it "shows the registered and trading address sections with their legends" do
      expect(page.all("fieldset legend", text: /address/i, visible: :all).size).to be >= 2
    end

    it "uses the portal error summary and not the shared one" do
      expect(response.body).not_to include("bg-red-50")
    end
  end
end
