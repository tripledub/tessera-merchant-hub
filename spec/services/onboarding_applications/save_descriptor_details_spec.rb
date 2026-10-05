# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::SaveDescriptorDetails do
  let(:application) do
    create(
      :onboarding_application,
      current_step: "descriptor",
      completed_steps: %w[company fulfilment currencies processing payments]
    )
  end

  it "saves descriptor details and advances the application" do
    result = described_class.call(application: application, attributes: {
      descriptor: "SPECIMEN SHOP",
      descriptor_company_number: "12345678",
      descriptor_company_city: "Testford"
    })

    expect(result).to be true
    expect(application.reload).to have_attributes(
      current_step: "volumes",
      completed_steps: %w[company fulfilment currencies processing payments descriptor],
      descriptor: "SPECIMEN SHOP",
      descriptor_company_number: "12345678",
      descriptor_company_city: "Testford"
    )
  end

  it "does not persist partial details or advance" do
    result = described_class.call(application: application, attributes: {
      descriptor: "SPECIMEN SHOP",
      descriptor_company_number: "",
      descriptor_company_city: ""
    })

    expect(result).to be false
    expect(application.reload).to have_attributes(current_step: "descriptor", descriptor: nil)
  end

  it "saves changes without moving backwards when revisiting the completed step" do
    application.update!(current_step: "volumes", completed_steps: %w[company fulfilment currencies processing payments descriptor])

    result = described_class.call(application: application, attributes: {
      descriptor: "UPDATED SHOP",
      descriptor_company_number: "87654321",
      descriptor_company_city: "Newtown"
    })

    expect(result).to be true
    expect(application.reload).to have_attributes(current_step: "volumes", descriptor: "UPDATED SHOP")
  end

  it "rejects a save before the descriptor step is reached" do
    application.update!(current_step: "payments", completed_steps: %w[company fulfilment currencies processing])

    expect do
      described_class.call(application: application, attributes: {
        descriptor: "SHOULD NOT SAVE",
        descriptor_company_number: "12345678",
        descriptor_company_city: "Testford"
      })
    end.to raise_error(OnboardingApplications::Advance::StepConflict)

    expect(application.reload).to have_attributes(current_step: "payments", descriptor: nil)
  end
end
