# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::AddressPopulationService do
  let(:applicant) { create(:applicant) }
  let(:principal) { create(:kyc_principal, applicant: applicant, name: "Jane Smith") }

  describe ".call" do
    context "when the document is a complete proof-of-address with a linked principal and no existing address" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          kyc_principal: principal,
          document_type: :bank_account_statement,
          status: :complete,
          extracted_data: {
            "account_holder" => "Jane Smith",
            "bank_name" => "Test Bank",
            "account_holder_address_line1" => "42 Oak Avenue",
            "account_holder_city" => "Manchester",
            "account_holder_postcode" => "M1 2AB",
            "account_holder_country" => "United Kingdom"
          })
      end

      it "populates the principal's address from the extracted data" do
        described_class.call(document)

        principal.reload
        expect(principal.address_line1).to eq("42 Oak Avenue")
        expect(principal.city).to eq("Manchester")
        expect(principal.postcode).to eq("M1 2AB")
        expect(principal.country).to eq("United Kingdom")
      end
    end

    context "when the principal already has an address" do
      let(:principal_with_address) do
        create(:kyc_principal, applicant: applicant, name: "Jane Smith", address_line1: "Existing Street")
      end

      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          kyc_principal: principal_with_address,
          document_type: :utility_bill,
          status: :complete,
          extracted_data: {
            "full_name" => "Jane Smith",
            "account_holder_address_line1" => "New Street",
            "account_holder_city" => "London",
            "account_holder_postcode" => "SW1A 1AA",
            "account_holder_country" => "United Kingdom"
          })
      end

      it "does not overwrite the existing address" do
        described_class.call(document)

        expect(principal_with_address.reload.address_line1).to eq("Existing Street")
      end
    end

    context "when the document has no linked principal" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :bank_account_statement,
          status: :complete,
          extracted_data: { "account_holder" => "Jane Smith" })
      end

      it "does nothing" do
        expect { described_class.call(document) }.not_to raise_error
      end
    end

    context "when the document is not a proof-of-address type" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          kyc_principal: principal,
          document_type: :passport,
          status: :complete,
          extracted_data: { "full_name" => "Jane Smith" })
      end

      it "does nothing" do
        described_class.call(document)

        expect(principal.reload.address_line1).to be_nil
      end
    end

    context "when the document is not yet complete" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          kyc_principal: principal,
          document_type: :bank_account_statement,
          status: :pending,
          extracted_data: nil)
      end

      it "does nothing" do
        expect { described_class.call(document) }.not_to raise_error
      end
    end
  end
end
