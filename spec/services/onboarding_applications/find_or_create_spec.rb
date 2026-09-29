# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::FindOrCreate do
  it "returns the application created by a concurrent request after a unique-index race" do
    applicant = create(:applicant)
    application = build_stubbed(:onboarding_application, applicant: applicant)
    allow(applicant).to receive(:onboarding_application).and_return(nil, application)
    allow(applicant).to receive(:create_onboarding_application!).and_raise(ActiveRecord::RecordNotUnique)
    allow(applicant).to receive(:reload).and_return(applicant)

    expect(described_class.call(applicant: applicant)).to eq(application)
  end

  it "reraises a creation failure when no concurrent application exists" do
    applicant = create(:applicant)
    allow(applicant).to receive_messages(onboarding_application: nil, reload: applicant)
    allow(applicant).to receive(:create_onboarding_application!).and_raise(ActiveRecord::RecordInvalid)

    expect { described_class.call(applicant: applicant) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
