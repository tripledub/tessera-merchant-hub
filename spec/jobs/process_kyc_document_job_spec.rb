# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessKycDocumentJob, type: :job do
  let(:applicant)  { create(:applicant) }
  let(:principal)  { create(:kyc_principal, applicant: applicant, name: "Jane Smith") }
  let(:document)   { create(:kyc_document, applicant: applicant) }

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

    it "leaves kyc_principal nil for non-passport documents with no match" do
      stub_request(:post, "#{ENV.fetch('KYNETIC_OCR_URL', 'http://localhost:8001')}/process")
        .to_return(status: 200, body: { "full_name" => "Jane Smith", "document_type" => "utility_bill" }.to_json,
                   headers: { "Content-Type" => "application/json" })
      described_class.new.perform(document.id)
      expect(document.reload.kyc_principal).to be_nil
    end

    it "broadcasts twice (processing + complete)" do
      described_class.new.perform(document.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).twice
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
        expect(document.result["error"]).to include('503')
      end
    end
  end
end
