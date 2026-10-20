# frozen_string_literal: true

require "rails_helper"

# MH-397: the applicant's dashboard in its three states.
RSpec.describe "Portal dashboard", type: :request do
  let(:user) { create(:applicant_user, :nameless) }

  before { sign_in user, scope: :applicant_user }

  def page
    Capybara.string(response.body)
  end

  def start_onboarding(**attributes)
    create(:onboarding_application, applicant: user.applicant, current_step: "fulfilment", completed_steps: [ "company" ], **attributes)
  end

  describe "not started" do
    before { get portal_root_path }

    it "greets the applicant, says how long it takes, and shows an empty bar" do
      expect(page).to have_css("h1", text: "Welcome back")
      expect(page).to have_text("Let's get your business set up. It takes about 10 minutes and you can stop and pick up later.")
      card = page.find("section", text: "Your onboarding")
      expect(card).to have_text("Not started")
      expect(card).to have_text("About 10 minutes")
      bar = card.find("[role='progressbar']")
      expect([ bar["aria-valuenow"], bar["aria-valuemin"], bar["aria-valuemax"] ]).to eq(%w[0 0 100])
      expect(bar["aria-label"]).to eq("Onboarding progress")
    end

    it "leads with the chat, offers the form, and says they save to the same application" do
      card = page.find("section", text: "Your onboarding")

      expect(card.find_link("Start onboarding")[:href]).to eq(portal_onboarding_path)
      expect(card.find_link("Use the form instead")[:href]).to eq(portal_application_path)
      expect(card).to have_text("Chat and form save to the same application, so you can switch at any time.")
      expect(card).to have_no_text("% complete")
    end

    it "does not show the password banner before anything has been completed" do
      expect(page).to have_no_css("#password-prompt")
    end
  end

  describe "in progress" do
    before do
      start_onboarding
      get portal_root_path
    end

    it "shows the percentage and what is next" do
      card = page.find("section", text: "Your onboarding")

      expect(card).to have_text("In progress")
      expect(card).to have_text(/\d+% complete\. Next up: Fulfilment and services/)
      expect(page).to have_text("Pick up where you left off. Your answers are saved as you go.")
    end

    it "keeps the bar and its text in step" do
      bar = page.find("[role='progressbar']")
      percent = bar["aria-valuenow"].to_i
      fill = bar.find(".kyn-progress-fill")

      expect(percent).to be_between(1, 99)
      expect(fill[:style]).to include("width: #{percent}%")
      expect(page).to have_text("#{percent}% complete")
    end

    it "leads with Continue in chat and offers the form" do
      card = page.find("section", text: "Your onboarding")

      expect(card.find_link("Continue in chat")[:href]).to eq(portal_onboarding_path)
      expect(card.find_link("Use the form instead")[:href]).to eq(portal_application_path)
    end

    it "shows the password banner once a step is completed, above the card" do
      banner = page.find("#password-prompt")

      expect(banner).to have_text("Sign in faster next time")
      expect(response.body.index("password-prompt")).to be < response.body.index("Your onboarding")
    end
  end

  describe "submitted" do
    before do
      start_onboarding(status: :submitted, current_step: "review", completed_steps: OnboardingApplication::STEPS)
      get portal_root_path
    end

    it "thanks the applicant and says what happens next" do
      expect(page).to have_css("h1", text: "Thank you")
      expect(page).to have_text("Your application has been sent to our team.")
      card = page.find("section", text: "Application submitted")
      expect(card).to have_text("We're reviewing your details. We'll email you if we need anything else.")
      expect(card).to have_text("Submitted")
    end

    it "links to the answers, and no longer offers the chat or the form to start" do
      expect(page.find_link("View your answers")[:href]).to eq(portal_application_path(step: "review"))
      expect(page).to have_no_link("Start onboarding")
      expect(page).to have_no_link("Continue in chat")
      expect(page).to have_no_link("Use the form instead")
    end
  end

  describe "the greeting" do
    it "uses the first name when there is one, in the open states" do
      user.update!(first_name: "Alex")

      get portal_root_path

      expect(page).to have_css("h1", text: "Welcome, Alex!")
    end

    it "still says Thank you when submitted, named or not" do
      user.update!(first_name: "Alex")
      start_onboarding(status: :submitted, current_step: "review", completed_steps: OnboardingApplication::STEPS)

      get portal_root_path

      expect(page).to have_css("h1", text: "Thank you")
    end
  end

  describe "the password link (MH-408)" do
    it "is on the dashboard in every state" do
      get portal_root_path
      expect(page.find("#password-link")).to have_button("Set a password")

      start_onboarding
      get portal_root_path
      expect(page.find("#password-link")).to have_button("Set a password")

      Applicant.find(user.applicant_id).onboarding_application.update!(status: :submitted, current_step: "review", completed_steps: OnboardingApplication::STEPS)
      get portal_root_path
      expect(page.find("#password-link")).to have_button("Set a password")
    end
  end

  describe "the look" do
    it "uses the applicant tokens: none of the old admin or dark classes" do
      start_onboarding
      get portal_root_path

      main = page.find("main").native.to_html
      expect(main).not_to match(/\bdark:|text-gray-|bg-gray-|border-gray-|bg-brand-|text-brand-|(?<!kyn-)btn-primary\b/)
    end

    it "carries no hard-coded English that is missing from the locale" do
      get portal_root_path

      expect(response.body).not_to include("Continue your KYC onboarding conversation")
      expect(response.body).not_to include("translation missing")
    end
  end
end
