# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::SaveFulfilmentDetails do
  subject(:save_details) { described_class.call(application: application, attributes: attributes) }

  let(:application) { create(:onboarding_application, current_step: "fulfilment", completed_steps: [ "company" ]) }
  let(:attributes) do
    {
      delivery_over_seven_days: true,
      full_payment_before_delivery: false,
      takes_deposits: true,
      deposit_percentage: "25.5",
      remaining_balance_due: "Seven days before delivery",
      service_requirements: "Hosted checkout and reporting",
      integration_type: "API"
    }
  end

  it "saves fulfilment answers and advances the application" do
    expect(save_details).to be true

    expect(application.reload).to have_attributes(
      delivery_over_seven_days: true,
      full_payment_before_delivery: false,
      takes_deposits: true,
      deposit_percentage: 25.5,
      remaining_balance_due: "Seven days before delivery",
      service_requirements: "Hosted checkout and reporting",
      integration_type: "API",
      current_step: "currencies",
      completed_steps: %w[company fulfilment]
    )
  end

  it "requires deposit details only when deposits are taken" do
    attributes[:deposit_percentage] = nil
    attributes[:remaining_balance_due] = nil

    expect(save_details).to be false
    expect(application.errors.of_kind?(:deposit_percentage, :blank)).to be true
    expect(application.errors.of_kind?(:remaining_balance_due, :blank)).to be true
    expect(application.reload.current_step).to eq("fulfilment")
  end

  it "clears stale deposit details when deposits are not taken" do
    application.update!(takes_deposits: true, deposit_percentage: 20, remaining_balance_due: "Before delivery")
    attributes.merge!(takes_deposits: false, deposit_percentage: "99", remaining_balance_due: "Stale answer")

    expect(save_details).to be true
    expect(application.reload).to have_attributes(
      takes_deposits: false,
      deposit_percentage: nil,
      remaining_balance_due: nil
    )
  end

  it "validates percentages within zero and one hundred" do
    attributes[:deposit_percentage] = "101"

    expect(save_details).to be false
    expect(application.errors[:deposit_percentage]).to include("must be less than or equal to 100")
  end

  it "updates a completed step without changing current progress" do
    application.update!(current_step: "processing", completed_steps: %w[company fulfilment currencies])

    expect(save_details).to be true
    expect(application.reload.current_step).to eq("processing")
  end

  it "rejects a save before the fulfilment step is reached" do
    application.update!(current_step: "company", completed_steps: [])

    expect { save_details }.to raise_error(OnboardingApplications::Advance::StepConflict)
    expect(application.reload).to have_attributes(
      current_step: "company",
      service_requirements: nil,
      integration_type: nil
    )
  end
end
