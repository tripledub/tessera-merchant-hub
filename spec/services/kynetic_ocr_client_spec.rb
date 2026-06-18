# frozen_string_literal: true

require "rails_helper"

RSpec.describe KyneticOcrClient do
  let(:base_url)      { "http://localhost:8001" }
  let(:document_key)  { "uploads/applicants/passport.pdf" }
  let(:customer_id)   { SecureRandom.uuid }
  let(:ocr_url)       { "#{base_url}/process" }
  let(:ocr_response)  { { "full_name" => "Jane Smith", "document_type" => "passport" } }

  describe ".process" do
    context "when the OCR service responds successfully" do
      before do
        stub_request(:post, ocr_url)
          .with(body: { customer_id: customer_id, document_key: document_key }.to_json,
                headers: { "Content-Type" => "application/json" })
          .to_return(status: 200, body: ocr_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns the parsed JSON response" do
        result = described_class.process(customer_id: customer_id, document_key: document_key)
        expect(result).to eq(ocr_response)
      end
    end

    context "when the OCR service returns a 5xx error" do
      before do
        stub_request(:post, ocr_url).to_return(status: 503, body: "Service Unavailable")
      end

      it "raises KyneticOcrClient::Error" do
        expect {
          described_class.process(customer_id: customer_id, document_key: document_key)
        }.to raise_error(KyneticOcrClient::Error, /503/)
      end
    end

    context "when the OCR service is unreachable" do
      before do
        stub_request(:post, ocr_url).to_raise(Faraday::ConnectionFailed.new("connection refused"))
      end

      it "raises KyneticOcrClient::Error" do
        expect {
          described_class.process(customer_id: customer_id, document_key: document_key)
        }.to raise_error(KyneticOcrClient::Error)
      end
    end
  end
end
