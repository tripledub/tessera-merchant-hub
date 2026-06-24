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

    # rubocop:disable RSpec/VerifiedDoubles
    # The Anthropic SDK response objects are dynamically generated and do not
    # expose stable Ruby classes for verified doubles.
    context "when running in test" do # rubocop:disable RSpec/ContextWording
      let(:applicant) { create(:applicant) }
      let(:document) { create(:kyc_document, applicant: applicant) }
      let(:api_key) { "test-api-key" }

      let(:content_block) { double("ContentBlock", text: extraction_json) }
      let(:claude_response) { double("MessagesResponse", content: [ content_block ]) }

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

      let(:messages_resource) { double("Messages") }
      let(:client_stub) { double("Anthropic::Client", messages: messages_resource) }

      before do
        allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return(api_key)
        allow(Anthropic::Client).to receive(:new).and_return(client_stub)
        allow(messages_resource).to receive(:create).and_return(claude_response)
      end

      it "returns parsed JSON from Claude's response" do
        result = described_class.process(document: document)

        expect(result).to include(
          "document_type" => "passport",
          "full_name" => "Jane Doe",
          "date_of_birth" => "1990-05-15"
        )
      end

      it "sends the document file as base64 to Claude" do
        described_class.process(document: document)

        expect(messages_resource).to have_received(:create).with(
          hash_including(
            model: "claude-opus-4-8",
            max_tokens: 1024
          )
        )
      end

      it "sends a PDF content block for PDF files" do
        described_class.process(document: document)

        expect(messages_resource).to have_received(:create).with(
          hash_including(
            messages: [
              hash_including(
                content: [
                  hash_including(type: "document", source: hash_including(media_type: "application/pdf")),
                  hash_including(type: "text")
                ]
              )
            ]
          )
        )
      end

      it "sends an image content block for image files" do
        document.file.attach(
          io: StringIO.new("fake image"),
          filename: "photo.jpg",
          content_type: "image/jpeg"
        )

        described_class.process(document: document)

        expect(messages_resource).to have_received(:create).with(
          hash_including(
            messages: [
              hash_including(
                content: [
                  hash_including(type: "image", source: hash_including(media_type: "image/jpeg")),
                  hash_including(type: "text")
                ]
              )
            ]
          )
        )
      end

      it "raises when Claude returns invalid JSON" do
        invalid_block = double("ContentBlock", text: "not json")
        invalid_response = double("MessagesResponse", content: [ invalid_block ])
        allow(messages_resource).to receive(:create).and_return(invalid_response)

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
    # rubocop:enable RSpec/VerifiedDoubles
  end
end
