# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingCurrency, type: :model do
  subject(:currency) { described_class.new(code: " gbp ", kind: :processing) }

  it { is_expected.to belong_to(:onboarding_application) }

  it "normalizes an ISO-style currency code" do
    currency.validate
    expect(currency.code).to eq("GBP")
  end

  it "rejects codes that are not three letters" do
    currency.code = "GB"
    expect(currency).not_to be_valid
  end
end
