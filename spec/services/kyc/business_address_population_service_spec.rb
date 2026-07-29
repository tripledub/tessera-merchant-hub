# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::BusinessAddressPopulationService do
  let(:applicant) { create(:applicant) }

  describe ".call" do
    context "when document is a complete proof-of-business-address with no existing primary address" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :certificate_of_registered_address,
          status: :complete,
          extracted_data: {
            "company_name" => "Acme Ltd",
            "line1" => "10 Business Park",
            "city" => "Bristol",
            "postcode" => "BS1 1AA",
            "country" => "United Kingdom"
          })
      end

      it "creates a primary Address::Business on the applicant" do
        described_class.call(document)

        address = applicant.addresses.find_by(type: "Address::Business", primary: true)
        expect(address).not_to be_nil
        expect(address.line1).to eq("10 Business Park")
        expect(address.city).to eq("Bristol")
        expect(address.postcode).to eq("BS1 1AA")
        expect(address.country).to eq("United Kingdom")
      end
    end

    context "when a primary business address already exists" do
      before do
        create(:address, :business, :primary, addressable: applicant, line1: "Existing HQ")
      end

      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :certificate_of_registered_address,
          status: :complete,
          extracted_data: {
            "company_name" => "Acme Ltd",
            "line1" => "New Address",
            "city" => "London",
            "postcode" => "EC1A 1BB",
            "country" => "United Kingdom"
          })
      end

      it "does not overwrite the existing primary address" do
        described_class.call(document)

        expect(applicant.addresses.where(primary: true).count).to eq(1)
        expect(applicant.primary_business_address.line1).to eq("Existing HQ")
      end

      it "does not raise if the presence check misses the address that already exists" do
        existing_address = applicant.primary_business_address
        allow(applicant).to receive(:primary_business_address).and_return(nil, existing_address)

        expect { described_class.call(document) }.not_to raise_error
        expect(applicant.addresses.where(primary: true).count).to eq(1)
        expect(applicant.primary_business_address.line1).to eq("Existing HQ")
      end
    end

    context "when the document is not a proof-of-business-address type" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :passport,
          status: :complete,
          extracted_data: { "full_name" => "Jane Smith" })
      end

      it "does nothing" do
        described_class.call(document)
        expect(applicant.addresses).to be_empty
      end
    end

    context "when the document has partial extraction data (line1 present but city and country missing)" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :certificate_of_registered_address,
          status: :complete,
          extracted_data: {
            "company_name" => "Acme Ltd",
            "line1" => "10 Business Park"
          })
      end

      it "does nothing and does not raise" do
        expect { described_class.call(document) }.not_to raise_error
        expect(applicant.addresses).to be_empty
      end
    end

    context "when the document is not yet complete" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :certificate_of_registered_address,
          status: :pending,
          extracted_data: nil)
      end

      it "does nothing" do
        expect { described_class.call(document) }.not_to raise_error
        expect(applicant.addresses).to be_empty
      end
    end
  end
end
