# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingSession, type: :model do
  subject(:onboarding_session) { build(:onboarding_session) }

  it { is_expected.to belong_to(:applicant) }
  it { is_expected.to have_many(:onboarding_messages).dependent(:destroy) }

  it do
    expect(onboarding_session).to define_enum_for(:current_stage)
      .with_values(
        company_info: 0,
        directors_ubos: 1,
        ownership: 2,
        business_activity: 3,
        jurisdictions: 4,
        document_collection: 5
      )
  end

  it do
    expect(onboarding_session).to define_enum_for(:status)
      .with_values(in_progress: 0, completed: 1, abandoned: 2)
  end

  it "is valid with valid attributes" do
    expect(onboarding_session).to be_valid
  end

  it "defaults current_stage to company_info" do
    expect(described_class.new.current_stage).to eq("company_info")
  end

  it "defaults completed_stages to an empty array" do
    expect(described_class.new.completed_stages).to eq([])
  end

  it "defaults stage_data to an empty hash" do
    expect(described_class.new.stage_data).to eq({})
  end

  it "defaults document_checklist to an empty hash" do
    expect(described_class.new.document_checklist).to eq({})
  end

  it "defaults status to in_progress" do
    expect(described_class.new.status).to eq("in_progress")
  end

  it "allows only one onboarding session per applicant" do
    applicant = create(:applicant)
    create(:onboarding_session, applicant: applicant)

    duplicate = build(:onboarding_session, applicant: applicant)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:applicant_id]).to include("has already been taken")
  end
end
