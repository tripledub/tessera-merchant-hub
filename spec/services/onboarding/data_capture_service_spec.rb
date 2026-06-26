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

    it "normalizes common date formats before storing looping stage data" do
      session = create(:onboarding_session, current_stage: :directors_ubos)

      described_class.call(session: session, extracted_data: {
        "full_name" => "Jane Smith",
        "date_of_birth" => "01/02/1980",
        "role" => "director"
      })

      expect(session.reload.stage_data["directors_ubos"]["current_item"]).to include(
        "date_of_birth" => "1980-02-01"
      )
    end

    it "normalizes common director and UBO role answers before storing looping stage data" do
      session = create(:onboarding_session, current_stage: :directors_ubos)

      described_class.call(session: session, extracted_data: {
        "full_name" => "Jane Smith",
        "role" => "director and UBO"
      })

      expect(session.reload.stage_data["directors_ubos"]["current_item"]).to include(
        "role" => "both"
      )
    end

    it "normalizes standalone UBO role answers as shareholder" do
      session = create(:onboarding_session, current_stage: :directors_ubos)

      described_class.call(session: session, extracted_data: {
        "full_name" => "Jane Smith",
        "role" => "UBO"
      })

      expect(session.reload.stage_data["directors_ubos"]["current_item"]).to include(
        "role" => "shareholder"
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

    it "updates the latest completed director item when role-only follow-up changes it to UBO too" do
      session = create(:onboarding_session, current_stage: :directors_ubos)
      described_class.call(session: session, extracted_data: director_payload.merge("role" => "director"))

      expect {
        described_class.call(session: session, extracted_data: { "role" => "UBO" })
      }.not_to change(KycPrincipal, :count)

      session.reload
      expect(session.stage_data["directors_ubos"]).to eq(
        "items" => [ director_payload.merge("role" => "both") ]
      )
      expect(KycPrincipal.last).to have_attributes(role: "director_and_psc")
    end

    it "does not guess which declared principal to update when the completed item cannot be matched by date of birth" do
      applicant = create(:applicant)
      older_principal = create_declared_principal(applicant, "1960-01-01")
      younger_principal = create_declared_principal(applicant, "1990-01-01")
      session = create(:onboarding_session, applicant: applicant, current_stage: :directors_ubos,
        stage_data: directors_ubos_data_missing_dob)

      described_class.call(session: session, extracted_data: { "role" => "UBO" })

      expect(older_principal.reload.role).to eq("director")
      expect(younger_principal.reload.role).to eq("director")
    end

    it "rolls back committed looping stage data when KYC record persistence fails" do
      session = create(:onboarding_session, current_stage: :directors_ubos)
      allow(KycPrincipal).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        described_class.call(session: session, extracted_data: director_payload)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(session.reload.stage_data).to eq({})
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

    it "stores human-readable ownership items as JSON without creating an ownership edge" do
      session = create(:onboarding_session, current_stage: :ownership)

      expect {
        described_class.call(session: session, extracted_data: {
          "owner" => "Patsy Pong",
          "owned_entity" => "McFoo & Sons",
          "percentage" => "31",
          "relationship_type" => "equity"
        })
      }.not_to change(Kyc::OwnershipEdge, :count)

      expect(session.reload.stage_data["ownership"]).to eq(
        "items" => [
          {
            "owner" => "Patsy Pong",
            "owned_entity" => "McFoo & Sons",
            "percentage" => "31",
            "relationship_type" => "equity"
          }
        ]
      )
    end

    it "keeps an incomplete ownership item when a new owner is captured before it is complete" do
      session = create(:onboarding_session, current_stage: :ownership, stage_data: incomplete_ownership_data)

      described_class.call(session: session, extracted_data: { "owner" => "Patsy Pong" })

      expect(session.reload.stage_data["ownership"]).to eq(incomplete_ownership_data_after_new_owner)
    end
  end

  def create_declared_principal(applicant, date_of_birth)
    create(:kyc_principal,
      applicant: applicant,
      name: "Jane Smith",
      date_of_birth: Date.iso8601(date_of_birth),
      role: :director,
      source: :applicant_declared)
  end

  def directors_ubos_data_missing_dob
    {
      "directors_ubos" => {
        "items" => [
          {
            "full_name" => "Jane Smith",
            "nationality" => "GB",
            "role" => "director"
          }
        ]
      }
    }
  end

  def incomplete_ownership_data
    {
      "ownership" => {
        "current_item" => {
          "owner" => "Stewart Campbell",
          "owned_entity" => "McFoo & Sons",
          "relationship_type" => "equity"
        }
      }
    }
  end

  def incomplete_ownership_data_after_new_owner
    {
      "current_item" => { "owner" => "Patsy Pong" },
      "incomplete_items" => [
        {
          "owner" => "Stewart Campbell",
          "owned_entity" => "McFoo & Sons",
          "relationship_type" => "equity"
        }
      ]
    }
  end
end
