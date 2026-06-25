# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentExtractorService, type: :service do
  let(:mock_adapter) { instance_double(Kyc::Inference::Base) }

  before do
    allow(Kyc::Inference).to receive(:adapter).and_return(mock_adapter)
  end

  describe ".call" do
    context "with a passport document" do
      let(:document) { create(:kyc_document, document_type: :passport) }
      let(:passport_response) do
        {
          "full_name" => "Aleksander Novak",
          "date_of_birth" => "1985-03-15",
          "document_number" => "AB1234567",
          "expiry_date" => "2030-01-01",
          "issuing_country" => "SI",
          "nationality" => "Slovenian",
          "issuing_authority" => "Ministry of Interior"
        }
      end

      before do
        allow(mock_adapter).to receive(:extract).and_return(passport_response)
      end

      it "extracts passport fields correctly" do
        result = described_class.call(document)

        expect(result).to eq(passport_response)
      end

      it "stores extracted_data on the document" do
        described_class.call(document)

        expect(document.reload.extracted_data).to eq(passport_response)
      end
    end

    context "with a utility bill document" do
      let(:document) { create(:kyc_document, document_type: :utility_bill) }
      let(:utility_bill_response) do
        {
          "full_name" => "Maria Bergsson",
          "address" => "42 Harbour Lane, Reykjavik",
          "provider" => "Nordic Energy Co",
          "issue_date" => "2025-11-01",
          "account_number" => "NE-998877"
        }
      end

      before do
        allow(mock_adapter).to receive(:extract).and_return(utility_bill_response)
      end

      it "extracts utility bill fields correctly" do
        result = described_class.call(document)

        expect(result).to eq(utility_bill_response)
      end
    end

    context "with a certificate_of_incorporation document" do
      let(:document) { create(:kyc_document, document_type: :certificate_of_incorporation) }
      let(:coi_response) do
        {
          "company_name" => "Meridian Ventures Ltd",
          "registration_number" => "12345678",
          "date_of_incorporation" => "2020-06-15",
          "jurisdiction" => "GB",
          "registered_address" => "10 Commerce Street, London"
        }
      end

      before do
        allow(mock_adapter).to receive(:extract).and_return(coi_response)
      end

      it "extracts certificate of incorporation fields correctly" do
        result = described_class.call(document)

        expect(result).to eq(coi_response)
      end
    end

    context "when inference raises an error" do
      let(:document) { create(:kyc_document, document_type: :passport) }

      before do
        allow(mock_adapter).to receive(:extract).and_raise(Kyc::Inference::Error, "model unavailable")
      end

      it "wraps the error in DocumentExtractorService::Error" do
        expect { described_class.call(document) }
          .to raise_error(Kyc::DocumentExtractorService::Error, /model unavailable/)
      end
    end
  end

  describe "#build_prompt" do
    let(:document) { create(:kyc_document, document_type: :passport) }
    let(:service) { described_class.new(document) }

    it "includes all schema field names in the prompt" do
      prompt = service.send(:build_prompt, ExtractionData::Passport)

      %w[full_name date_of_birth document_number expiry_date issuing_country nationality issuing_authority].each do |field|
        expect(prompt).to include(%("#{field}"))
      end
    end

    it "uses YYYY-MM-DD hint for date fields" do
      prompt = service.send(:build_prompt, ExtractionData::Passport)

      expect(prompt).to include('"date_of_birth": "YYYY-MM-DD or null"')
      expect(prompt).to include('"expiry_date": "YYYY-MM-DD or null"')
    end

    it "uses string hint for string fields" do
      prompt = service.send(:build_prompt, ExtractionData::Passport)

      expect(prompt).to include('"full_name": "string or null"')
    end
  end

  describe "generic fallback" do
    let(:document) { create(:kyc_document, document_type: :passport) }

    before do
      allow(ExtractionData::Base).to receive(:for).and_return(ExtractionData::Generic)
      allow(mock_adapter).to receive(:extract).and_return({})
    end

    it "works with the Generic schema as a fallback" do
      expect { described_class.call(document) }.not_to raise_error
    end

    it "uses a generic open-ended prompt when schema has no attributes" do
      described_class.call(document)
      expect(mock_adapter).to have_received(:extract).with(
        document: document,
        prompt: include("Extract all relevant information")
      )
    end
  end
end
