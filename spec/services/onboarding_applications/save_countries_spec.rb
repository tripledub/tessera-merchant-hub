# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::SaveCountries do
  subject(:save_countries) { described_class.call(application: application, attributes: attributes) }

  let(:application) do
    create(:onboarding_application, current_step: "countries", completed_steps: %w[company volumes])
  end
  let(:attributes) { { target_country_codes: [ "", "gb", "US" ] } }

  it "stores the selected countries and advances" do
    expect(save_countries).to be true
    expect(application.reload).to have_attributes(
      current_step: "principals",
      completed_steps: %w[company volumes countries]
    )
    expect(application.onboarding_countries.pluck(:code)).to contain_exactly("GB", "US")
  end

  it "requires at least one country" do
    attributes[:target_country_codes] = [ "" ]

    expect(save_countries).to be false
    expect(application.errors.of_kind?(:onboarding_countries, :blank)).to be true
    expect(application.reload.current_step).to eq("countries")
  end

  it "rejects countries outside the sample list" do
    attributes[:target_country_codes] = %w[GB ZZ]

    expect(save_countries).to be false
    expect(application.reload.onboarding_countries).to be_empty
  end

  it "replaces the saved selection when revisiting without moving backwards" do
    application.onboarding_countries.create!(code: "GB")
    application.onboarding_countries.create!(code: "FR")
    application.update!(current_step: "principals", completed_steps: %w[company volumes countries])
    attributes[:target_country_codes] = %w[GB DE]

    expect(save_countries).to be true
    expect(application.reload.current_step).to eq("principals")
    expect(application.onboarding_countries.pluck(:code)).to contain_exactly("GB", "DE")
  end

  it "rejects a save before the countries step is reached" do
    application.update!(current_step: "volumes", completed_steps: [ "company" ])

    expect { save_countries }.to raise_error(OnboardingApplications::Advance::StepConflict)
    expect(application.reload.onboarding_countries).to be_empty
  end
end
