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
    app/views/portal/applications/_fulfilment_fields.html.erb
    app/views/portal/applications/_currency_fields.html.erb
    app/views/portal/applications/_currency_item_fields.html.erb
    app/views/portal/applications/_processing_fields.html.erb
    app/views/portal/applications/_payment_fields.html.erb
    app/views/portal/applications/_descriptor_fields.html.erb
    app/views/portal/applications/_country_fields.html.erb
    app/javascript/controllers/country_picker_controller.js
    app/views/portal/applications/_principal_fields.html.erb
    app/views/portal/applications/_principal_item_fields.html.erb
    app/views/portal/applications/_review.html.erb
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

  describe "steps 2 to 8 (MH-424)" do
    def render_step(step, **application_attributes)
      OnboardingApplication.where(applicant: applicant_user.applicant).destroy_all
      completed = OnboardingApplication::STEPS.take_while { |candidate| candidate != step }
      create(:onboarding_application, applicant: applicant_user.applicant, current_step: step,
                                      completed_steps: completed, **application_attributes)
      get portal_application_path(step: step)
    end

    %w[fulfilment currencies processing payments descriptor countries].each do |step|
      it "renders #{step} with the Kynetic controls and the portal error summary" do
        render_step(step)

        expect(response).to have_http_status(:ok)
        expect(page).to have_css("form .kyn-label, form legend.kyn-label, form label.kyn-label")
        expect(page).to have_css("form input[type='submit'].kyn-btn-primary[value='Save and continue']")
        expect(response.body).not_to include("form-input")
      end
    end

    it "gives every Yes/No question round kyn radios in 44px labels" do
      render_step("fulfilment")

      expect(page.all("input[type='radio']", visible: :all).size).to eq(6)
      expect(page.all("input[type='radio'].kyn-radio", visible: :all).size).to eq(6)
      expect(page).to have_css("label.kyn-check-label", minimum: 6)
    end

    it "keeps the conditional fields hidden until their answer is Yes" do
      render_step("processing")

      expect(page).to have_css("[data-conditional-fields-target='dependent'][hidden]", visible: :all)
    end

    it "keeps the no-JavaScript country list as a plain multi-select with the kyn input look" do
      render_step("countries")

      expect(page).to have_css("select#country-picker-select.kyn-input[multiple]", visible: :all)
    end
  end

  describe "principals and review (MH-425)" do
    def open_step(step, **attributes)
      OnboardingApplication.where(applicant: applicant_user.applicant).destroy_all
      completed = OnboardingApplication::STEPS.take_while { |candidate| candidate != step }
      create(:onboarding_application, applicant: applicant_user.applicant, current_step: step,
                                      completed_steps: completed, **attributes)
      get portal_application_path(step: step)
    end

    it "renders the principals step with kyn fields and the role names unchanged" do
      open_step("principals")

      expect(page).to have_css("input.kyn-input[name*='[name]']", visible: :all)
      expect(page).to have_css("input[type='date'].kyn-input", visible: :all)
      expect(page).to have_css("input[type='email'].kyn-input", visible: :all)
      expect(page).to have_css("select.kyn-input option", text: "Director & PSC", visible: :all)
      expect(page).to have_css("input[type='submit'].kyn-btn-primary", visible: :all)
    end

    it "shows a blank answer on the review page in red, with a link to fix it" do
      open_step("review")

      missing = page.all("[data-testid='review-missing']")
      expect(missing).not_to be_empty
      expect(missing.first.text.squish).to include("Missing. Add this before you submit.")
      expect(missing.first).to have_css("a[href*='/portal/application?step=']", text: "Add this before you submit.")
      expect(missing.first[:class]).to include("text-kyn-error")
    end

    it "says so when there are no principals, and links to that step" do
      open_step("review")

      principals_card = page.all("section.kyn-card").find { |card| card.has_css?("h3", text: "Directors and beneficial owners") }
      expect(principals_card).to have_css("a[href='#{portal_application_path(step: 'principals')}']", text: "Add this before you submit.")
    end

    it "lists the principals with their role" do
      OnboardingApplication.where(applicant: applicant_user.applicant).destroy_all
      application = create(:onboarding_application, applicant: applicant_user.applicant, current_step: "review",
                                                    completed_steps: OnboardingApplication::STEPS - [ "review" ])
      create(:kyc_principal, applicant: application.applicant, name: "Test Principal", role: :director_and_psc)
      get portal_application_path(step: "review")

      expect(page).to have_css("li", text: "Test Principal — Director & PSC")
    end

    it "does not wrap the review cards in another card" do
      open_step("review")

      expect(page).to have_no_css("section.kyn-card section.kyn-card")
      expect(page).to have_css("input[type='submit'].kyn-btn-primary[value='Submit application']")
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
