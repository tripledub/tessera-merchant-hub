# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Inference::ClaudeAdapter, type: :service do
  let(:mock_response) { instance_double(RubyLLM::Message, content: { "result" => "some data" }) }
  let(:mock_chat)     { instance_double(RubyLLM::Chat) }

  before do
    allow(mock_chat).to receive_messages(ask: mock_response, with_schema: mock_chat)
  end

  describe "#extract" do
    let(:document) { create(:kyc_document, document_type: :group_structure_chart) }
    let(:prompt) { "Extract data from this document." }

    it "returns parsed result from the model response" do
      adapter = described_class.new(client: mock_chat)
      result = adapter.extract(document: document, prompt: prompt)

      expect(result).to eq("result" => "some data")
    end

    it "passes the prompt to the model with the document file" do
      adapter = described_class.new(client: mock_chat)
      adapter.extract(document: document, prompt: prompt)

      expect(mock_chat).to have_received(:ask).with(prompt, with: anything)
    end

    it "raises Kyc::Inference::Error on invalid JSON from a string response" do
      bad_response = instance_double(RubyLLM::Message, content: "not json")
      allow(mock_chat).to receive(:ask).and_return(bad_response)

      adapter = described_class.new(client: mock_chat)

      expect { adapter.extract(document: document, prompt: prompt) }
        .to raise_error(Kyc::Inference::Error, /invalid JSON/i)
    end

    it "falls back to RubyLLM.chat when no client injected" do
      allow(RubyLLM).to receive(:chat).with(model: described_class::MODEL_ID).and_return(mock_chat)

      adapter = described_class.new
      result = adapter.extract(document: document, prompt: prompt)

      expect(result).to eq("result" => "some data")
      expect(RubyLLM).to have_received(:chat).with(model: described_class::MODEL_ID)
    end
  end

  describe "#generate" do
    it "returns a Hash directly when response content is already a Hash" do
      adapter = described_class.new(client: mock_chat)
      result = adapter.generate(prompt: "Reply with JSON.")

      expect(result).to eq("result" => "some data")
    end

    it "parses JSON when response content is a string" do
      string_response = instance_double(RubyLLM::Message, content: '{"result":"some data"}')
      allow(mock_chat).to receive(:ask).and_return(string_response)

      adapter = described_class.new(client: mock_chat)
      result = adapter.generate(prompt: "Reply with JSON.")

      expect(result).to eq("result" => "some data")
    end
  end
end
