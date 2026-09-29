# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::Submit do
  it "submits a complete review-ready application" do
    application = complete_application

    expect(described_class.call(application: application)).to be true
    expect(application.reload).to be_submitted
    expect(application.submitted_at).to be_present
  end

  it "does not submit when required information is missing" do
    application = complete_application
    application.update_column(:descriptor, nil)

    expect(described_class.call(application: application)).to be false
    expect(application.reload).to be_draft
    expect(application.errors[:descriptor]).to include("can't be blank")
  end

  it "rejects submission before the review step" do
    application = complete_application
    application.update!(current_step: "principals", completed_steps: application.completed_steps - [ "principals" ])

    expect { described_class.call(application: application) }
      .to raise_error(OnboardingApplications::Advance::StepConflict)
    expect(application.reload).to be_draft
  end

  def complete_application
    applicant = create(:applicant, company_number: "12345678")
    create(:address, :business, :primary, addressable: applicant)
    create(:address, :primary, type: "Address::Trading", addressable: applicant)
    create(:applicant_domain, applicant: applicant)
    create(:kyc_principal, applicant: applicant, source: :applicant_declared,
      date_of_birth: Date.new(1980, 1, 2), email: "owner@example.com")
    application = create(:onboarding_application, applicant: applicant, current_step: "review",
      completed_steps: OnboardingApplication::STEPS - [ "review" ], **required_answers)
    application.processing_currencies.create!(code: "GBP")
    application.settlement_currencies.create!(code: "GBP")
    application
  end

  def required_answers
    {
      business_model_description: "Online retail", operating_licence: "None required",
      delivery_over_seven_days: false, full_payment_before_delivery: true, takes_deposits: false,
      service_requirements: "Card payments", integration_type: "API",
      currently_accepts_card_payments: false, uses_shopping_cart: false, takes_recurring_payments: false,
      descriptor: "SPECIMEN", descriptor_company_number: "12345678", descriptor_company_city: "London"
    }
  end
end
