# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplication, type: :model do
  subject(:application) { build(:onboarding_application) }

  it { is_expected.to belong_to(:applicant) }
  it { is_expected.to validate_uniqueness_of(:applicant_id).ignoring_case_sensitivity }

  it "starts as a draft on the company step" do
    expect(described_class.new).to have_attributes(status: "draft", current_step: "company")
  end

  it "defines the ordered self-service sections" do
    expect(described_class::STEPS).to eq(%w[
      company fulfilment currencies processing pricing volumes countries principals review
    ])
  end
end
