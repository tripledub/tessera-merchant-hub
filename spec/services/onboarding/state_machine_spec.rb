# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::StateMachine do
  describe ".current_stage" do
    it "returns the session current stage as a symbol" do
      session = build(:onboarding_session, current_stage: :directors_ubos)

      expect(described_class.current_stage(session)).to eq(:directors_ubos)
    end
  end

  describe ".missing_fields" do
    it "returns required fields not yet collected for the current stage" do
      session = build(:onboarding_session, current_stage: :company_info, stage_data: {
        "company_info" => {
          "company_name" => "Acme Ltd",
          "registration_number" => "12345678"
        }
      })

      expect(described_class.missing_fields(session)).to eq(
        %i[company_type registered_address country_of_incorporation]
      )
    end

    it "uses current_item sub-state for looping stages" do
      session = build(:onboarding_session, current_stage: :directors_ubos, stage_data: {
        "directors_ubos" => {
          "items" => [
            {
              "full_name" => "Jane Smith",
              "date_of_birth" => "1980-01-01",
              "nationality" => "GB",
              "role" => "director"
            }
          ],
          "current_item" => {
            "full_name" => "Joe Bloggs"
          },
          "current_index" => 1
        }
      })

      expect(described_class.missing_fields(session)).to eq(%i[date_of_birth nationality role])
    end
  end

  describe ".validate_field" do
    it "validates string fields" do
      expect(described_class.validate_field(:company_name, "Acme Ltd")).to eq(valid: true)
      expect(described_class.validate_field(:company_name, " ")).to include(valid: false)
    end

    it "validates date fields" do
      expect(described_class.validate_field(:date_of_birth, "1980-01-01")).to eq(valid: true)
      expect(described_class.validate_field(:date_of_birth, "not-a-date")).to include(valid: false)
    end

    it "validates decimal fields" do
      expect(described_class.validate_field(:percentage, "25.5")).to eq(valid: true)
      expect(described_class.validate_field(:percentage, "abc")).to include(valid: false)
    end

    it "validates option fields" do
      expect(described_class.validate_field(:role, "both")).to eq(valid: true)
      expect(described_class.validate_field(:role, "owner")).to include(valid: false)
    end

    it "rejects unknown fields" do
      expect(described_class.validate_field(:unknown_field, "value")).to include(valid: false)
    end
  end

  describe ".stage_complete?" do
    it "returns true when all required fields are collected and valid" do
      session = build(:onboarding_session, current_stage: :business_activity, stage_data: {
        "business_activity" => {
          "industry" => "Software",
          "business_description" => "Sells compliance tooling"
        }
      })

      expect(described_class.stage_complete?(session)).to be(true)
    end

    it "returns false when a required field is invalid" do
      session = build(:onboarding_session, current_stage: :business_activity, stage_data: {
        "business_activity" => {
          "industry" => "Software",
          "business_description" => " "
        }
      })

      expect(described_class.stage_complete?(session)).to be(false)
    end

    it "requires at least one complete item for a looping stage" do
      complete_session = build(:onboarding_session, current_stage: :jurisdictions, stage_data: {
        "jurisdictions" => {
          "items" => [
            { "country" => "GB", "licence_type" => "EMI" }
          ]
        }
      })
      empty_session = build(:onboarding_session, current_stage: :jurisdictions, stage_data: {
        "jurisdictions" => { "items" => [] }
      })

      expect(described_class.stage_complete?(complete_session)).to be(true)
      expect(described_class.stage_complete?(empty_session)).to be(false)
    end

    it "returns false while a looping stage has a partial current item" do
      session = build(:onboarding_session, current_stage: :ownership, stage_data: {
        "ownership" => {
          "items" => [
            {
              "owner" => "person-1",
              "owned_entity" => "company-1",
              "percentage" => "50",
              "relationship_type" => "equity"
            }
          ],
          "current_item" => {
            "owner" => "person-2"
          }
        }
      })

      expect(described_class.stage_complete?(session)).to be(false)
    end

    it "requires ownership percentage for equity relationships" do
      session = build(:onboarding_session, current_stage: :ownership, stage_data: {
        "ownership" => {
          "items" => [
            {
              "owner" => "person-1",
              "owned_entity" => "company-1",
              "relationship_type" => "equity"
            }
          ]
        }
      })

      expect(described_class.stage_complete?(session)).to be(false)
    end

    it "does not require ownership percentage for nominee relationships" do
      session = build(:onboarding_session, current_stage: :ownership, stage_data: {
        "ownership" => {
          "items" => [
            {
              "owner" => "person-1",
              "owned_entity" => "company-1",
              "relationship_type" => "nominee"
            }
          ]
        }
      })

      expect(described_class.stage_complete?(session)).to be(true)
    end
  end

  describe ".advance!" do
    it "moves a complete session to the next stage and records the completed stage" do
      session = create(:onboarding_session, current_stage: :company_info, stage_data: {
        "company_info" => {
          "company_name" => "Acme Ltd",
          "registration_number" => "12345678",
          "company_type" => "limited_company",
          "registered_address" => "1 High Street",
          "country_of_incorporation" => "GB"
        }
      })

      expect(described_class.advance!(session)).to eq(:directors_ubos)
      expect(session.reload.current_stage).to eq("directors_ubos")
      expect(session.completed_stages).to eq([ "company_info" ])
    end

    it "raises when the current stage is incomplete" do
      session = build(:onboarding_session, current_stage: :company_info)

      expect {
        described_class.advance!(session)
      }.to raise_error(Onboarding::StateMachine::IncompleteStageError)
    end

    it "marks the session completed at the final stage" do
      session = create(:onboarding_session, current_stage: :document_collection)

      expect(described_class.advance!(session)).to eq(:completed)
      expect(session.reload.status).to eq("completed")
      expect(session.completed_stages).to eq([ "document_collection" ])
    end
  end

  describe ".can_go_back?" do
    it "returns false at the first stage" do
      session = build(:onboarding_session, current_stage: :company_info)

      expect(described_class.can_go_back?(session)).to be(false)
    end

    it "returns true after the first stage" do
      session = build(:onboarding_session, current_stage: :ownership)

      expect(described_class.can_go_back?(session)).to be(true)
    end
  end

  describe ".go_back!" do
    it "returns to a previous stage and removes later completed stages" do
      session = create(:onboarding_session,
        current_stage: :business_activity,
        completed_stages: %w[company_info directors_ubos ownership])

      expect(described_class.go_back!(session, :directors_ubos)).to eq(:directors_ubos)
      expect(session.reload.current_stage).to eq("directors_ubos")
      expect(session.completed_stages).to eq([ "company_info" ])
    end

    it "raises when asked to go to a later stage" do
      session = build(:onboarding_session, current_stage: :directors_ubos)

      expect {
        described_class.go_back!(session, :ownership)
      }.to raise_error(Onboarding::StateMachine::InvalidTransitionError)
    end
  end
end
