# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingCountry, type: :model do
  subject(:country) { described_class.new(onboarding_application: create(:onboarding_application), code: " gb ") }

  it { is_expected.to belong_to(:onboarding_application) }

  it "normalizes the code to upper case" do
    country.validate
    expect(country.code).to eq("GB")
  end

  it "only accepts codes from the sample country list" do
    expect(described_class::SAMPLE_CODES).to include("GB", "US")

    country.code = "ZZ"
    expect(country).not_to be_valid
    expect(country.errors.of_kind?(:code, :inclusion)).to be true
  end

  it "is unique per application" do
    country.save!
    duplicate = described_class.new(onboarding_application: country.onboarding_application, code: "GB")

    expect(duplicate).not_to be_valid
  end
end
