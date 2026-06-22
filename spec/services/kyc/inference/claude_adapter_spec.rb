# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Inference::ClaudeAdapter, type: :service do
  describe "#extract" do
    let(:document) { create(:kyc_document, document_type: :group_structure_chart) }
    let(:prompt) { "Extract data from this document." }

    let(:claude_response_text) do
      { "result" => "some data" }.to_json
    end

    let(:mock_message) do
      instance_double(Anthropic::Models::Message,
        content: [ instance_double(Anthropic::Models::TextBlock, text: claude_response_text) ])
    end

    let(:mock_messages) do
      instance_double(Anthropic::Resources::Messages, create: mock_message)
    end

    let(:mock_client) do
      instance_double(Anthropic::Client, messages: mock_messages)
    end

    it "returns parsed JSON from the model response" do
      adapter = described_class.new(client: mock_client)
      result = adapter.extract(document: document, prompt: prompt)

      expect(result).to eq("result" => "some data")
    end

    it "passes the prompt to the model" do
      adapter = described_class.new(client: mock_client)
      adapter.extract(document: document, prompt: prompt)

      expect(mock_messages).to have_received(:create).with(
        hash_including(
          messages: [
            hash_including(content: include(hash_including(type: "text", text: prompt)))
          ]
        )
      )
    end

    it "raises Kyc::Inference::Error on invalid JSON" do
      bad_message = instance_double(Anthropic::Models::Message,
        content: [ instance_double(Anthropic::Models::TextBlock, text: "not json") ])
      allow(mock_messages).to receive(:create).and_return(bad_message)

      adapter = described_class.new(client: mock_client)

      expect { adapter.extract(document: document, prompt: prompt) }
        .to raise_error(Kyc::Inference::Error, /invalid JSON/i)
    end

    it "falls back to credentials when no client injected" do
      allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return("test-key")
      allow(Anthropic::Client).to receive(:new).and_return(mock_client)

      adapter = described_class.new
      result = adapter.extract(document: document, prompt: prompt)

      expect(result).to eq("result" => "some data")
      expect(Anthropic::Client).to have_received(:new).with(api_key: "test-key")
    end
  end
end
