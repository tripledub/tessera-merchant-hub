# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::Advance do
  it "marks the current step complete and persists the next step" do
    application = create(:onboarding_application, current_step: "company")

    described_class.call(application: application, step: "company")

    expect(application.reload).to have_attributes(
      current_step: "fulfilment",
      completed_steps: [ "company" ],
      status: "draft"
    )
  end

  it "does not let a stale page skip the persisted current step" do
    application = create(:onboarding_application, current_step: "processing")

    expect {
      described_class.call(application: application, step: "company")
    }.to raise_error(OnboardingApplications::Advance::StepConflict)
  end

  it "keeps review as the current step until submission is implemented" do
    application = create(:onboarding_application, current_step: "review")

    described_class.call(application: application, step: "review")

    expect(application.reload).to have_attributes(current_step: "review", status: "draft")
    expect(application.completed_steps).to include("review")
  end
end
