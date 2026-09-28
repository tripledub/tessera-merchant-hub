# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::SavePaymentDetails do
  let(:application) do
    create(:onboarding_application, current_step: "payments", completed_steps: %w[company fulfilment currencies processing])
  end

  it "saves conditional payment details and advances the application" do
    result = described_class.call(application: application, attributes: {
      uses_shopping_cart: true,
      shopping_cart_provider: "Specimen Cart",
      takes_recurring_payments: true,
      sends_recurring_payment_receipts: true,
      sends_recurring_payment_advance_notifications: false
    })

    expect(result).to be true
    expect(application.reload).to have_attributes(
      current_step: "descriptor",
      completed_steps: %w[company fulfilment currencies processing payments],
      shopping_cart_provider: "Specimen Cart",
      sends_recurring_payment_receipts: true,
      sends_recurring_payment_advance_notifications: false
    )
  end

  it "does not advance when conditional answers are missing" do
    result = described_class.call(application: application, attributes: {
      uses_shopping_cart: true,
      shopping_cart_provider: "",
      takes_recurring_payments: true
    })

    expect(result).to be false
    expect(application.current_step).to eq("payments")
  end

  it "clears stale conditional values when their parent answers change to no" do
    application.update!(
      shopping_cart_provider: "Old Cart",
      sends_recurring_payment_receipts: true,
      sends_recurring_payment_advance_notifications: true
    )

    described_class.call(application: application, attributes: {
      uses_shopping_cart: false,
      takes_recurring_payments: false
    })

    expect(application.reload).to have_attributes(
      shopping_cart_provider: nil,
      sends_recurring_payment_receipts: nil,
      sends_recurring_payment_advance_notifications: nil
    )
  end
end
