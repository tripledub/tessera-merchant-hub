# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::Profile, type: :model do
  subject(:profile) { build(:registry_profile) }

  describe "associations" do
    it { is_expected.to belong_to(:applicant) }
    it { is_expected.to have_many(:directors).class_name("Registry::Director").dependent(:destroy) }
    it { is_expected.to have_many(:addresses).class_name("Registry::Address").dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:jurisdiction) }
    it { is_expected.to validate_presence_of(:company_number) }
    it { is_expected.to validate_presence_of(:company_name) }
    it { is_expected.to validate_presence_of(:fetched_at) }
  end

  it "is valid with valid attributes" do
    expect(profile).to be_valid
  end

  it "persists raw_response as jsonb" do
    profile.raw_response = { "foo" => "bar" }
    profile.save!

    expect(profile.reload.raw_response).to eq("foo" => "bar")
  end

  it "creates a new row per fetch attempt rather than updating" do
    applicant = create(:applicant)
    first = create(:registry_profile, applicant: applicant, company_number: "123")
    second = create(:registry_profile, applicant: applicant, company_number: "123")

    expect(applicant.registry_profiles.reload).to contain_exactly(first, second)
  end
end
