# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::DataCaptureService do
  describe ".call" do
    let(:director_payload) do
      {
        "full_name" => "Jane Smith",
        "date_of_birth" => "1980-01-01",
        "nationality" => "GB",
        "role" => "both",
        "residential_address" => "1 High Street"
      }
    end

    it "persists valid non-looping stage data and rejects invalid values" do
      session = create(:onboarding_session, current_stage: :company_info)

      result = described_class.call(session: session, extracted_data: {
        "company_name" => "Acme Ltd",
        "registration_number" => "12345678",
        "company_type" => "limited_company",
        "registered_address" => "1 High Street",
        "country_of_incorporation" => "GB",
        "unknown_field" => "ignored",
        "business_description" => " "
      })

      expect(result).to eq(
        "company_name" => "Acme Ltd",
        "registration_number" => "12345678",
        "company_type" => "limited_company",
        "registered_address" => "1 High Street",
        "country_of_incorporation" => "GB"
      )
      expect(session.reload.stage_data["company_info"]).to eq(result)
    end

    it "merges looping stage values into current_item until the item is complete" do
      session = create(:onboarding_session, current_stage: :directors_ubos)

      described_class.call(session: session, extracted_data: {
        "full_name" => "Jane Smith",
        "role" => "director"
      })

      expect(session.reload.stage_data["directors_ubos"]).to eq(
        "current_item" => {
          "full_name" => "Jane Smith",
          "role" => "director"
        }
      )
    end

    it "commits a complete directors_ubos item and creates an applicant-declared principal" do
      session = create(:onboarding_session, current_stage: :directors_ubos)

      expect {
        described_class.call(session: session, extracted_data: director_payload)
      }.to change(KycPrincipal, :count).by(1)

      session.reload
      expect(session.stage_data["directors_ubos"]).to eq("items" => [ director_payload ])
      expect(KycPrincipal.last).to have_attributes(
        applicant: session.applicant,
        name: "Jane Smith",
        date_of_birth: Date.iso8601("1980-01-01"),
        role: "director_and_psc",
        source: "applicant_declared"
      )
    end

    it "updates JSON only for business activity and jurisdictions" do
      business_session = create(:onboarding_session, current_stage: :business_activity)
      jurisdictions_session = create(:onboarding_session, current_stage: :jurisdictions)

      described_class.call(session: business_session, extracted_data: {
        "industry" => "Software",
        "business_description" => "Compliance tooling"
      })
      described_class.call(session: jurisdictions_session, extracted_data: {
        "country" => "GB",
        "licence_type" => "EMI"
      })

      expect(business_session.reload.stage_data["business_activity"]).to include(
        "industry" => "Software",
        "business_description" => "Compliance tooling"
      )
      expect(jurisdictions_session.reload.stage_data["jurisdictions"]["items"]).to eq([
        { "country" => "GB", "licence_type" => "EMI" }
      ])
    end

    it "creates ownership edges when supplied entity references are valid" do
      applicant = create(:applicant)
      parent_entity = create(:kyc_corporate_entity, applicant: applicant)
      child_entity = create(:kyc_corporate_entity, applicant: applicant)
      session = create(:onboarding_session, applicant: applicant, current_stage: :ownership)

      expect {
        described_class.call(session: session, extracted_data: {
          "owner" => parent_entity.id,
          "owned_entity" => child_entity.id,
          "percentage" => "75",
          "relationship_type" => "equity"
        })
      }.to change(Kyc::OwnershipEdge, :count).by(1)

      expect(Kyc::OwnershipEdge.last).to have_attributes(
        parent_entity: parent_entity,
        child_entity: child_entity,
        percentage: BigDecimal("75"),
        relationship_type: "equity",
        source: "applicant_declared"
      )
    end
  end
end
