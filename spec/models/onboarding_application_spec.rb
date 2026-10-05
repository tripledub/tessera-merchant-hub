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
      company fulfilment currencies processing payments descriptor volumes countries principals review
    ])
  end

  describe "target countries" do
    it "requires at least one country on the countries step and at submission" do
      application = create(:onboarding_application)

      expect(application.valid?(:countries)).to be false
      expect(application.errors.of_kind?(:onboarding_countries, :blank)).to be true
      expect(application.valid?(:submission)).to be false
      expect(application.errors.of_kind?(:onboarding_countries, :blank)).to be true
    end

    it "exposes the selected codes through target_country_codes" do
      application = create(:onboarding_application)
      application.target_country_codes = %w[gb de]

      expect(application.target_country_codes).to contain_exactly("GB", "DE")
      expect(application.valid?(:countries)).to be true
    end

    it "does not count unselected countries" do
      application = create(:onboarding_application)
      application.onboarding_countries.create!(code: "GB")
      application.target_country_codes = []

      expect(application.target_country_codes).to be_empty
      expect(application.valid?(:countries)).to be false
    end
  end

  describe "payment details validation" do
    it "requires a provider when a shopping cart is used" do
      application.assign_attributes(uses_shopping_cart: true, shopping_cart_provider: "")

      expect(application).not_to be_valid(:payments)
      expect(application.errors.of_kind?(:shopping_cart_provider, :blank)).to be true
    end

    it "requires receipt and notification answers for recurring payments" do
      application.assign_attributes(takes_recurring_payments: true)

      expect(application).not_to be_valid(:payments)
      expect(application.errors.of_kind?(:sends_recurring_payment_receipts, :inclusion)).to be true
      expect(application.errors.of_kind?(:sends_recurring_payment_advance_notifications, :inclusion)).to be true
    end
  end

  it "requires all descriptor details" do
    application.assign_attributes(descriptor: "", descriptor_company_number: "", descriptor_company_city: "")

    expect(application).not_to be_valid(:descriptor)
    expect(application.errors.attribute_names).to include(
      :descriptor, :descriptor_company_number, :descriptor_company_city
    )
  end
end
