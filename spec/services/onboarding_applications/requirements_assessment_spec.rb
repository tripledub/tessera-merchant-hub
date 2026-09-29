# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::RequirementsAssessment, type: :service do
  it "does not evaluate an application before it is submitted" do
    application = create(:onboarding_application)

    expect(described_class.for(application)).to be_nil
  end

  it "uses submission validations to identify missing information" do
    application = create(:onboarding_application, status: :submitted)

    result = described_class.for(application)

    expect(result.missing_information).to include("Business model description can't be blank")
  end

  it "uses the shared KYC policy to identify required and missing documents" do
    applicant = create(:applicant, sector: :crypto_exchange)
    application = create(:onboarding_application, applicant: applicant, status: :submitted)

    result = described_class.for(application)

    expect(result.required_documents).to contain_exactly(
      "vasp_registration", "wallet_custody_infrastructure_attestation"
    )
    expect(result.missing_documents).to contain_exactly(
      "vasp_registration", "wallet_custody_infrastructure_attestation"
    )
  end

  it "recognises documents already collected by the existing document workflow" do
    applicant = create(:applicant, sector: :crypto_exchange)
    create(:kyc_document, applicant: applicant, document_type: :vasp_registration)
    application = create(:onboarding_application, applicant: applicant, status: :submitted)

    result = described_class.for(application)

    expect(result.required_documents).to include("vasp_registration")
    expect(result.missing_documents).not_to include("vasp_registration")
    expect(result.missing_documents).to include("wallet_custody_infrastructure_attestation")
  end
end
