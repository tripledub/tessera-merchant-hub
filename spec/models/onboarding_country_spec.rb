# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingCountry, type: :model do
  subject(:country) { described_class.new(onboarding_application: create(:onboarding_application), code: " gb ") }

  it { is_expected.to belong_to(:onboarding_application) }

  it "normalizes the code to upper case" do
    country.validate
    expect(country.code).to eq("GB")
  end

  it "accepts any ISO 3166-1 country code" do
    %w[GB US CZ NZ].each do |code|
      country.code = code
      expect(country).to be_valid
    end
  end

  it "rejects codes that are not ISO 3166-1 countries" do
    country.code = "ZZ"
    expect(country).not_to be_valid
    expect(country.errors.of_kind?(:code, :inclusion)).to be true
  end

  it "exposes common English names sorted by name" do
    expect(described_class.names).to include("GB" => "United Kingdom", "US" => "United States")
    expect(described_class.options.map(&:first)).to eq(described_class.options.map(&:first).sort)
    country.validate
    expect(country.name).to eq("United Kingdom")
  end

  it "is unique per application" do
    country.save!
    duplicate = described_class.new(onboarding_application: country.onboarding_application, code: "GB")

    expect(duplicate).not_to be_valid
  end
end
