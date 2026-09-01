# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractionData do
  describe "Base.for" do
    it "returns Passport model for passport type" do
      expect(ExtractionData::Base.for(:passport)).to eq(ExtractionData::Passport)
    end

    it "returns Generic model for unknown type" do
      expect(ExtractionData::Base.for(:unknown)).to eq(ExtractionData::Generic)
    end

    it "returns VaspRegistration model for vasp_registration type" do
      expect(ExtractionData::Base.for(:vasp_registration)).to eq(ExtractionData::VaspRegistration)
    end

    it "returns WalletCustodyInfrastructureAttestation model for wallet custody attestation type" do
      expect(ExtractionData::Base.for(:wallet_custody_infrastructure_attestation)).to eq(
        ExtractionData::WalletCustodyInfrastructureAttestation
      )
    end

    it "has every document type registered, except types intentionally never extracted" do
      # "other" acknowledges a document without extracting it (ExtractKycDocumentJob
      # refuses to run for it) — it deliberately has no dedicated schema to extract into.
      never_extracted = %w[other]

      (KycDocument.document_types.keys - never_extracted).each do |type|
        model = ExtractionData::Base.for(type)
        expect(model).not_to eq(ExtractionData::Generic), "Expected #{type} to have a registered ExtractionData model"
      end
    end

    it "falls back to Generic for other, since it is never extracted" do
      expect(ExtractionData::Base.for(:other)).to eq(ExtractionData::Generic)
    end
  end

  describe ExtractionData::Passport do
    it "validates required fields" do
      passport = described_class.new
      expect(passport).not_to be_valid
      expect(passport.errors[:full_name]).to be_present
      expect(passport.errors[:document_number]).to be_present
      expect(passport.errors[:expiry_date]).to be_present
    end

    it "is valid with required fields" do
      passport = described_class.new(
        full_name: "John Smith",
        document_number: "AB123456",
        expiry_date: "2030-01-01"
      )
      expect(passport).to be_valid
    end

    it "casts date attributes" do
      passport = described_class.new(date_of_birth: "1990-05-15")
      expect(passport.date_of_birth).to eq(Date.new(1990, 5, 15))
    end
  end

  describe ExtractionData::UtilityBill do
    it "has structured account holder address fields" do
      bill = described_class.new(
        account_holder_address_line1: "42 Oak Avenue",
        account_holder_city: "Manchester",
        account_holder_postcode: "M1 2AB",
        account_holder_country: "United Kingdom"
      )
      expect(bill.account_holder_address_line1).to eq("42 Oak Avenue")
      expect(bill.account_holder_city).to eq("Manchester")
    end
  end

  describe ExtractionData::CertificateOfIncorporation do
    it "validates required fields" do
      cert = described_class.new
      expect(cert).not_to be_valid
      expect(cert.errors[:company_name]).to be_present
      expect(cert.errors[:registration_number]).to be_present
    end
  end

  describe ExtractionData::BankAccountStatement do
    it "validates required fields" do
      stmt = described_class.new
      expect(stmt).not_to be_valid
      expect(stmt.errors[:account_holder]).to be_present
      expect(stmt.errors[:bank_name]).to be_present
    end

    it "is valid with required fields" do
      stmt = described_class.new(
        account_holder: "Acme Ltd",
        bank_name: "Example Bank",
        account_number: "12345678",
        currency: "GBP"
      )
      expect(stmt).to be_valid
    end
  end

  describe ExtractionData::VaspRegistration do
    it "casts registration and authorisation dates" do
      registration = described_class.new(
        registration_date: "2024-01-15",
        authorisation_date: "2024-02-01"
      )

      expect(registration.registration_date).to eq(Date.new(2024, 1, 15))
      expect(registration.authorisation_date).to eq(Date.new(2024, 2, 1))
    end
  end

  describe ExtractionData::WalletCustodyInfrastructureAttestation do
    it "retains provider, custody, and storage descriptions" do
      attestation = described_class.new(
        provider_name: "Example Custody Provider",
        custody_description: "Institutional custody",
        storage_description: "Offline key storage"
      )

      expect(attestation.provider_name).to eq("Example Custody Provider")
      expect(attestation.custody_description).to eq("Institutional custody")
      expect(attestation.storage_description).to eq("Offline key storage")
    end
  end

  describe "KycDocument#typed_extracted_data" do
    let(:document) do
      create(:kyc_document,
        document_type: :passport,
        classification_status: :confirmed,
        extracted_data: {
          "full_name" => "John Smith",
          "document_number" => "AB123456",
          "expiry_date" => "2030-01-01",
          "nationality" => "GB"
        })
    end

    it "returns a typed store model instance" do
      data = document.typed_extracted_data
      expect(data).to be_a(ExtractionData::Passport)
      expect(data.full_name).to eq("John Smith")
      expect(data.document_number).to eq("AB123456")
      expect(data.nationality).to eq("GB")
    end

    it "returns nil when no extracted data" do
      doc = create(:kyc_document, document_type: :passport, extracted_data: {})
      expect(doc.typed_extracted_data).to be_nil
    end

    it "returns nil when no document type" do
      doc = create(:kyc_document, document_type: nil, extracted_data: { "full_name" => "Test" })
      expect(doc.typed_extracted_data).to be_nil
    end
  end

  describe "KycDocument#extraction_schema" do
    it "returns the correct schema for the document type" do
      doc = build(:kyc_document, document_type: :bank_account_statement)
      expect(doc.extraction_schema).to eq(ExtractionData::BankAccountStatement)
    end
  end
end
