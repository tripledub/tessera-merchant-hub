# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::SaveCompanyDetails do
  subject(:save_details) { described_class.call(application: application, attributes: attributes) }

  let(:applicant) { create(:applicant, company_name: nil, company_number: nil) }
  let(:application) { create(:onboarding_application, applicant: applicant) }
  let(:attributes) do
    {
      business_model_description: "Online retail of specimen widgets.",
      eu_entity_details: "Example EU GmbH, Berlin",
      referrer: "Example Partner",
      test_login_details: "Sandbox account available on request",
      operating_licence: "None required",
      applicant_attributes: {
        id: applicant.id,
        company_name: "Specimen Widgets Ltd",
        company_number: "12345678",
        sector: "general",
        primary_business_address_attributes: address_attributes("1 Test Street"),
        trading_address_attributes: address_attributes("2 Example Road"),
        applicant_domains_attributes: {
          "0" => { name: "specimen-widgets.example" },
          "1" => { name: "shop.specimen-widgets.example" }
        }
      }
    }
  end

  def address_attributes(line1)
    { line1: line1, city: "Testford", postcode: "TE1 1ST", country: "United Kingdom" }
  end

  it "stores company answers in the shared application and applicant domain" do
    expect(save_details).to be true

    expect(application.reload).to have_attributes(
      business_model_description: "Online retail of specimen widgets.",
      eu_entity_details: "Example EU GmbH, Berlin",
      referrer: "Example Partner",
      test_login_details: "Sandbox account available on request",
      operating_licence: "None required",
      current_step: "fulfilment",
      completed_steps: [ "company" ]
    )
    expect(applicant.reload).to have_attributes(company_name: "Specimen Widgets Ltd", company_number: "12345678")
    expect(applicant.primary_business_address).to have_attributes(
      type: "Address::Business", line1: "1 Test Street", primary: true
    )
    expect(applicant.trading_address).to have_attributes(type: "Address::Trading", line1: "2 Example Road", primary: true)
    expect(applicant.applicant_domains.pluck(:name)).to contain_exactly(
      "specimen-widgets.example", "shop.specimen-widgets.example"
    )
  end

  it "does not advance or persist partial data when required company details are invalid" do
    attributes[:business_model_description] = ""
    attributes[:applicant_attributes][:primary_business_address_attributes][:city] = ""

    expect(save_details).to be false
    expect(application.reload).to have_attributes(current_step: "company", business_model_description: nil)
    expect(applicant.reload.company_name).to be_nil
  end

  it "updates a completed company step without moving the current step backwards" do
    application.update!(current_step: "processing", completed_steps: %w[company fulfilment currencies])

    expect(save_details).to be true
    expect(application.reload.current_step).to eq("processing")
  end

  it "keeps valid company details when another request advances the step first" do
    allow(OnboardingApplications::Advance).to receive(:call) do
      OnboardingApplication.where(id: application.id).update_all(
        current_step: "fulfilment", completed_steps: [ "company" ]
      )
      raise OnboardingApplications::Advance::StepConflict
    end

    expect(save_details).to be true
    expect(application).to have_attributes(current_step: "fulfilment", completed_steps: [ "company" ])
    expect(application.reload.business_model_description).to eq("Online retail of specimen widgets.")
    expect(applicant.reload.company_name).to eq("Specimen Widgets Ltd")
  end
end
