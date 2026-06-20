# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractKycDocumentJob, type: :job do
  let(:applicant) { create(:applicant) }
  let(:principal) { create(:kyc_principal, applicant: applicant, name: "Jane Smith") }
  let(:document) do
    create(:kyc_document,
      applicant: applicant,
      document_type: :passport,
      classification_status: :confirmed)
  end

  let(:ocr_response) { { "full_name" => "Jane Smith", "document_type" => "passport" } }

  before do
    stub_request(:post, "#{ENV.fetch('KYNETIC_OCR_URL', 'http://localhost:8001')}/process")
      .to_return(status: 200, body: ocr_response.to_json, headers: { "Content-Type" => "application/json" })
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "transitions document to complete and stores result" do
      described_class.new.perform(document.id)
      document.reload
      expect(document.status).to eq("complete")
      expect(document.result).to eq(ocr_response)
    end

    it "auto-matches principal by full_name" do
      principal
      described_class.new.perform(document.id)
      expect(document.reload.kyc_principal).to eq(principal)
    end

    it "creates an unconfirmed principal from a passport when no match exists" do
      expect { described_class.new.perform(document.id) }
        .to change(KycPrincipal, :count).by(1)
      principal = document.reload.kyc_principal
      expect(principal).to be_present
      expect(principal).to be_unconfirmed
      expect(principal.name).to eq("Jane Smith")
    end

    it "broadcasts twice (processing + complete)" do
      described_class.new.perform(document.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).twice
    end

    context "when classification is not confirmed" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :passport,
          classification_status: :auto_classified)
      end

      it "skips extraction" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.status).to eq("pending")
        expect(document.result).to be_nil
      end
    end

    context "when address matching runs for a utility bill with a principal present" do
      let(:principal_with_address) do
        create(:kyc_principal,
          applicant: applicant,
          name: "Jane Smith",
          address_line1: "12 High Street",
          city: "London",
          postcode: "SW1A 1AA",
          country: "United Kingdom")
      end

      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :utility_bill,
          classification_status: :confirmed)
      end

      before do
        principal_with_address
        stub_request(:post, "#{ENV.fetch('KYNETIC_OCR_URL', 'http://localhost:8001')}/process")
          .to_return(
            status: 200,
            body: {
              "full_name" => "Jane Smith",
              "document_type" => "utility_bill",
              "address" => "12 High Street, London, SW1A 1AA, United Kingdom"
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "stores address_match_method and address_match_confidence" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.address_match_method).to eq("exact")
        expect(document.address_match_confidence).to be_present
      end
    end

    context "when OCR service fails" do
      before do
        stub_request(:post, "#{ENV.fetch('KYNETIC_OCR_URL', 'http://localhost:8001')}/process")
          .to_return(status: 503, body: "Service Unavailable")
      end

      it "transitions document to error" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.status).to eq("error")
        expect(document.result["error"]).to include("503")
      end
    end
  end
end
