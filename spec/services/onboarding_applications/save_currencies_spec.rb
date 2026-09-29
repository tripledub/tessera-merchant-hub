# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::SaveCurrencies do
  subject(:save_currencies) { described_class.call(application: application, attributes: attributes) }

  let(:application) { create(:onboarding_application, current_step: "currencies", completed_steps: %w[company fulfilment]) }
  let(:attributes) do
    {
      processing_currencies_attributes: { "0" => { code: "gbp" }, "1" => { code: "EUR" } },
      settlement_currencies_attributes: { "0" => { code: "GBP" } }
    }
  end

  it "stores normalized currency records and advances" do
    expect(save_currencies).to be true
    expect(application.reload).to have_attributes(
      current_step: "processing",
      completed_steps: %w[company fulfilment currencies]
    )
    expect(application.processing_currencies.pluck(:code)).to contain_exactly("GBP", "EUR")
    expect(application.settlement_currencies.pluck(:code)).to contain_exactly("GBP")
  end

  it "requires at least one currency of each kind" do
    attributes[:settlement_currencies_attributes] = {}

    expect(save_currencies).to be false
    expect(application.errors.of_kind?(:settlement_currencies, :blank)).to be true
    expect(application.reload.current_step).to eq("currencies")
  end

  it "keeps malformed codes on the affected nested record" do
    attributes[:processing_currencies_attributes]["0"][:code] = "sterling"

    expect(save_currencies).to be false
    expect(application.processing_currencies.first.errors.of_kind?(:code, :invalid)).to be true
  end

  it "rejects a save before the currencies step is reached" do
    application.update!(current_step: "fulfilment", completed_steps: [ "company" ])

    expect { save_currencies }.to raise_error(OnboardingApplications::Advance::StepConflict)
    expect(application.reload.processing_currencies).to be_empty
    expect(application.settlement_currencies).to be_empty
  end
end
