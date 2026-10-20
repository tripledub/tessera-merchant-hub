# frozen_string_literal: true

require "rails_helper"

# MH-397: what the applicant's dashboard shows: which of three states they are in,
# how far along they are and what comes next, from the same snapshot the chat and
# the form share.
RSpec.describe ApplicantDashboardPresenter, type: :presenter do
  let(:template) do
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.view_context
  end
  let(:user) { create(:applicant_user, :nameless) }
  let(:applicant) { user.applicant }
  let(:presenter) { described_class.new(user.reload, template) }

  def application(**attributes)
    @application ||= create(:onboarding_application, applicant: applicant, **attributes)
  end

  describe "#state" do
    it "is not started with no application at all" do
      expect(presenter.state).to eq(:not_started)
    end

    it "is not started for a draft with nothing answered" do
      application

      expect(presenter.state).to eq(:not_started)
    end

    it "is in progress once a form step has been completed" do
      application(current_step: "fulfilment", completed_steps: [ "company" ])

      expect(presenter.state).to eq(:in_progress)
    end

    it "is in progress once the applicant has said something in the chat" do
      application
      session = create(:onboarding_session, applicant: applicant)
      create(:onboarding_message, onboarding_session: session, role: :applicant, content: "Hello")

      expect(presenter.state).to eq(:in_progress)
    end

    it "is not started when only the assistant has spoken" do
      application
      session = create(:onboarding_session, applicant: applicant)
      create(:onboarding_message, onboarding_session: session, role: :bot, content: "Welcome")

      expect(presenter.state).to eq(:not_started)
    end

    it "is submitted once the application has been submitted" do
      application(status: :submitted, current_step: "review", completed_steps: OnboardingApplication::STEPS)

      expect(presenter.state).to eq(:submitted)
    end
  end

  describe "#percentage" do
    it "is 0 before anything is answered" do
      application

      expect(presenter.percentage).to eq(0)
    end

    it "counts an answer given only in the chat" do
      application(current_step: "company")
      create(:onboarding_session, applicant: applicant,
             stage_data: { "company_info" => { "company_type" => "Limited company", "country_of_incorporation" => "United Kingdom" } })

      expect(presenter.percentage).to be_positive
      expect(presenter.state).to eq(:in_progress)
    end

    it "never reaches 100 while something is still missing" do
      application(completed_steps: [ "company" ], current_step: "fulfilment")
      snapshot = instance_double(OnboardingApplications::Snapshot,
        progress: OnboardingApplications::Snapshot::Progress.new(done: 99, total: 100),
        next_action: OnboardingApplications::Snapshot::NextAction.new(step: "chat", message: "x"))
      allow(OnboardingApplications::Snapshot).to receive(:for).and_return(snapshot)

      expect(presenter.percentage).to eq(99)
    end

    it "is 100 only when nothing is missing" do
      application(completed_steps: [ "company" ], current_step: "review")
      snapshot = instance_double(OnboardingApplications::Snapshot,
        progress: OnboardingApplications::Snapshot::Progress.new(done: 30, total: 30), next_action: nil)
      allow(OnboardingApplications::Snapshot).to receive(:for).and_return(snapshot)

      expect(presenter.percentage).to eq(100)
    end
  end

  describe "#next_up" do
    def with_next_action(next_action)
      application(completed_steps: [ "company" ], current_step: "fulfilment")
      snapshot = instance_double(OnboardingApplications::Snapshot,
        progress: OnboardingApplications::Snapshot::Progress.new(done: 1, total: 30), next_action: next_action)
      allow(OnboardingApplications::Snapshot).to receive(:for).and_return(snapshot)
    end

    it "names the first step to do for an applicant who has not begun" do
      expect(presenter.next_up).to eq("Company details")
    end

    it "names the form step that has a gap" do
      with_next_action(OnboardingApplications::Snapshot::NextAction.new(step: "currencies", message: "x"))

      expect(presenter.next_up).to eq("Currencies and settlement")
    end

    it "points at the chat when only chat questions are left" do
      with_next_action(OnboardingApplications::Snapshot::NextAction.new(step: "chat", message: "x"))

      expect(presenter.next_up).to eq("A few questions in the chat")
    end

    it "points at documents when only documents are left" do
      with_next_action(OnboardingApplications::Snapshot::NextAction.new(step: "documents", message: "x"))

      expect(presenter.next_up).to eq("Upload documents")
    end

    it "says review and submit when nothing is missing" do
      with_next_action(nil)

      expect(presenter.next_up).to eq("Review and submit")
    end
  end

  describe "#heading" do
    it "greets a named applicant by first name" do
      user.update!(first_name: "Alex")

      expect(presenter.heading).to eq("Welcome, Alex!")
    end

    it "greets an unnamed applicant plainly" do
      expect(presenter.heading).to eq("Welcome back")
    end

    it "says thank you once submitted, named or not" do
      user.update!(first_name: "Alex")
      application(status: :submitted, current_step: "review", completed_steps: OnboardingApplication::STEPS)

      expect(presenter.heading).to eq("Thank you")
    end
  end

  describe "#intro" do
    it "has a line for each state" do
      expect(presenter.intro).to include("It takes about 10 minutes")

      application(current_step: "fulfilment", completed_steps: [ "company" ])
      presenter_in_progress = described_class.new(user.reload, template)
      expect(presenter_in_progress.intro).to include("Pick up where you left off")

      application.update!(status: :submitted, current_step: "review", completed_steps: OnboardingApplication::STEPS)
      expect(described_class.new(user.reload, template).intro).to eq("Your application has been sent to our team.")
    end
  end
end
