# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::SaveProcessingHistory do
  let(:application) { create(:onboarding_application, current_step: "processing", completed_steps: %w[company fulfilment currencies]) }

  it "requires and saves an acquirer when cards are accepted" do
    expect(described_class.call(application: application, attributes: {
      currently_accepts_card_payments: true, current_acquirer: "Specimen Bank"
    })).to be true
    expect(application.reload).to have_attributes(current_step: "pricing", current_acquirer: "Specimen Bank")
  end

  it "rejects a missing acquirer when cards are accepted" do
    expect(described_class.call(application: application, attributes: {
      currently_accepts_card_payments: true, current_acquirer: ""
    })).to be false
    expect(application.errors.of_kind?(:current_acquirer, :blank)).to be true
  end

  it "clears a stale acquirer when cards are not accepted" do
    application.update!(current_acquirer: "Old Bank")
    described_class.call(application: application, attributes: { currently_accepts_card_payments: false })
    expect(application.reload.current_acquirer).to be_nil
  end
end
