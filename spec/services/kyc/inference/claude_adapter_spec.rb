# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Inference::ClaudeAdapter, type: :service do
  describe "#extract_group_structure" do
    let(:document) { create(:kyc_document, document_type: :group_structure_chart) }

    let(:claude_response_text) do
      {
        entities: [
          { name: "Maple Holdings Ltd", type: "corporate", jurisdiction: "GB" },
          { name: "Jane Doe", type: "individual", jurisdiction: nil },
          { name: "Birch Trading Ltd", type: "corporate", jurisdiction: "CY" }
        ],
        edges: [
          { parent: "Jane Doe", child: "Maple Holdings Ltd", relationship_type: "equity", percentage: 100.0 },
          { parent: "Maple Holdings Ltd", child: "Birch Trading Ltd", relationship_type: "equity", percentage: 75.0 }
        ]
      }.to_json
    end

    let(:mock_message) do
      instance_double(Anthropic::Models::Message, content: [ instance_double(Anthropic::Models::TextBlock, text: claude_response_text) ])
    end

    let(:mock_messages) do
      instance_double(Anthropic::Resources::Messages, create: mock_message)
    end

    let(:mock_client) do
      instance_double(Anthropic::Client, messages: mock_messages)
    end

    before do
      allow(Anthropic::Client).to receive(:new).and_return(mock_client)
      allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return("test-key")
    end

    it "returns a hash with entities and edges keys" do
      result = described_class.new.extract_group_structure(document)

      expect(result).to have_key(:entities)
      expect(result).to have_key(:edges)
    end

    it "parses entities correctly" do
      result = described_class.new.extract_group_structure(document)

      expect(result[:entities]).to contain_exactly(
        a_hash_including(name: "Maple Holdings Ltd", type: "corporate"),
        a_hash_including(name: "Jane Doe", type: "individual"),
        a_hash_including(name: "Birch Trading Ltd", type: "corporate")
      )
    end

    it "parses edges correctly" do
      result = described_class.new.extract_group_structure(document)

      expect(result[:edges]).to contain_exactly(
        a_hash_including(parent: "Jane Doe", child: "Maple Holdings Ltd", relationship_type: "equity", percentage: 100.0),
        a_hash_including(parent: "Maple Holdings Ltd", child: "Birch Trading Ltd", relationship_type: "equity", percentage: 75.0)
      )
    end

    it "raises Kyc::Inference::Error on invalid JSON from Claude" do
      bad_message = instance_double(Anthropic::Models::Message,
        content: [ instance_double(Anthropic::Models::TextBlock, text: "not json") ])
      allow(mock_messages).to receive(:create).and_return(bad_message)

      expect { described_class.new.extract_group_structure(document) }
        .to raise_error(Kyc::Inference::Error, /invalid JSON/i)
    end
  end
end
