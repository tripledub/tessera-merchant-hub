# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClaudeOcrAdapter, type: :model do
  describe ".process" do
    context "when running in production" do
      it "raises an error" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

        document = instance_double(KycDocument)
        expect {
          described_class.process(document: document)
        }.to raise_error(ClaudeOcrAdapter::Error, /must not be used in production/)
      end
    end

    context "when running in test" do # rubocop:disable RSpec/ContextWording
      let(:applicant) { create(:applicant) }
      let(:document) { create(:kyc_document, applicant: applicant) }

      let(:extraction_json) do
        {
          "document_type" => "passport",
          "full_name" => "Jane Doe",
          "date_of_birth" => "1990-05-15",
          "document_number" => "AB123456",
          "issuing_country" => "GB",
          "issuing_authority" => nil,
          "expiry_date" => "2030-12-31",
          "address" => nil
        }.to_json
      end

      let(:mock_response) { instance_double(RubyLLM::Message, content: extraction_json) }
      let(:mock_chat) { instance_double(RubyLLM::Chat) }

      before do
        allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return("test-api-key")
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
      end

      it "returns parsed JSON from Claude's response" do
        result = described_class.process(document: document)

        expect(result).to include(
          "document_type" => "passport",
          "full_name" => "Jane Doe",
          "date_of_birth" => "1990-05-15"
        )
      end

      it "uses the opus model" do
        described_class.process(document: document)

        expect(RubyLLM).to have_received(:chat).with(model: "claude-opus-4-8")
      end

      it "sends the document file to Claude as an attachment" do
        described_class.process(document: document)

        expect(mock_chat).to have_received(:ask).with(anything, with: anything)
      end

      it "raises when Claude returns invalid JSON" do
        invalid_response = instance_double(RubyLLM::Message, content: "not json")
        allow(mock_chat).to receive(:ask).and_return(invalid_response)

        expect {
          described_class.process(document: document)
        }.to raise_error(ClaudeOcrAdapter::Error, /invalid JSON/)
      end

      it "raises when the API key is not configured" do
        allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return(nil)

        expect {
          described_class.process(document: document)
        }.to raise_error(ClaudeOcrAdapter::Error, /anthropic_api_key not set/)
      end
    end
  end
end
