# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentDateConfirmation, type: :model do
  let_it_be(:actor) { create(:user, :psp_admin) }
  let_it_be(:document) do
    create(:kyc_document, validity_dates: {
             "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01", "confidence" => 0.95,
                           "provenance" => "ai_extraction" },
             "issued" => { "raw" => nil, "normalized" => nil, "confidence" => nil, "provenance" => "ai_extraction" }
           })
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:date_role) }
    it { is_expected.to validate_presence_of(:confirmed_value) }

    it "is invalid when date_role is not one of the document's extracted validity_dates roles" do
      confirmation = described_class.new(
        kyc_document: document, date_role: "bogus_role",
        confirmed_value: Date.new(2030, 1, 1), confirmed_by: actor
      )

      expect(confirmation).not_to be_valid
      expect(confirmation.errors[:date_role]).to be_present
    end

    it "is valid when date_role matches one of the document's extracted validity_dates roles" do
      confirmation = described_class.new(
        kyc_document: document, date_role: "issued",
        confirmed_value: Date.new(2020, 1, 1), confirmed_by: actor
      )

      expect(confirmation).to be_valid
    end

    it "is invalid for any date_role when the document has no extracted validity_dates at all" do
      inert_document = create(:kyc_document, validity_dates: {})
      confirmation = described_class.new(
        kyc_document: inert_document, date_role: "expiry",
        confirmed_value: Date.new(2030, 1, 1), confirmed_by: actor
      )

      expect(confirmation).not_to be_valid
      expect(confirmation.errors[:date_role]).to be_present
    end

    it "is valid without a reason when nothing changed" do
      confirmation = described_class.new(
        kyc_document: document, date_role: "expiry",
        extracted_value: Date.new(2030, 1, 1), confirmed_value: Date.new(2030, 1, 1),
        confirmed_by: actor
      )

      expect(confirmation).to be_valid
    end

    it "requires a non-blank reason when confirmed_value differs from extracted_value" do
      confirmation = described_class.new(
        kyc_document: document, date_role: "expiry",
        extracted_value: Date.new(2030, 1, 1), confirmed_value: Date.new(2031, 1, 1),
        confirmed_by: actor, reason: ""
      )

      expect(confirmation).not_to be_valid
      expect(confirmation.errors[:reason]).to be_present
    end

    it "is valid without a reason when there was no extracted value to begin with (missing date entry)" do
      confirmation = described_class.new(
        kyc_document: document, date_role: "expiry",
        extracted_value: nil, confirmed_value: Date.new(2030, 1, 1),
        confirmed_by: actor
      )

      expect(confirmation).to be_valid
    end

    it "is valid with a reason when confirmed_value differs from extracted_value" do
      confirmation = described_class.new(
        kyc_document: document, date_role: "expiry",
        extracted_value: Date.new(2030, 1, 1), confirmed_value: Date.new(2031, 1, 1),
        confirmed_by: actor, reason: "Corrected typo from passport scan"
      )

      expect(confirmation).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:kyc_document) }
    it { is_expected.to belong_to(:confirmed_by).class_name("User") }
  end

  describe ".current_for" do
    it "returns nil when there are no confirmations for the role" do
      expect(described_class.current_for(document, "expiry")).to be_nil
    end

    it "returns the most recent confirmation for the document and role" do
      first = described_class.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2030, 1, 1), confirmed_by: actor
      )
      travel_to(first.created_at + 1.minute) do
        second = described_class.create!(
          kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
          confirmed_value: Date.new(2031, 1, 1), confirmed_by: actor, reason: "Corrected"
        )

        expect(described_class.current_for(document, "expiry")).to eq(second)
      end
    end

    it "does not destroy or update earlier confirmations when a later one is created" do
      first = described_class.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2030, 1, 1), confirmed_by: actor
      )
      described_class.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2031, 1, 1), confirmed_by: actor, reason: "Corrected"
      )

      expect(described_class.count).to eq(2)
      expect(first.reload.confirmed_value).to eq(Date.new(2030, 1, 1))
    end

    it "scopes lookups to the given date_role" do
      described_class.create!(
        kyc_document: document, date_role: "issued", extracted_value: Date.new(2020, 1, 1),
        confirmed_value: Date.new(2020, 1, 1), confirmed_by: actor
      )

      expect(described_class.current_for(document, "expiry")).to be_nil
    end
  end

  describe "append-only audit trail" do
    it "keeps history of all confirmations for a document and role" do
      described_class.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2030, 1, 1), confirmed_by: actor
      )
      described_class.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2031, 1, 1), confirmed_by: actor, reason: "Corrected"
      )

      expect(document.date_confirmations.where(date_role: "expiry").count).to eq(2)
    end
  end
end
