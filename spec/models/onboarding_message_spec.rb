# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingMessage, type: :model do
  subject(:onboarding_message) { build(:onboarding_message) }

  it { is_expected.to belong_to(:onboarding_session) }

  it do
    expect(onboarding_message).to define_enum_for(:role)
      .with_values(bot: 0, applicant: 1)
  end

  it "is valid with valid attributes" do
    expect(onboarding_message).to be_valid
  end

  it "requires content" do
    onboarding_message.content = nil

    expect(onboarding_message).not_to be_valid
    expect(onboarding_message.errors[:content]).to include("can't be blank")
  end

  it "defaults structured_data to an empty hash" do
    expect(described_class.new.structured_data).to eq({})
  end
end
