# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/schema"

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

    context "when a schema is provided" do
      let(:schema) { Class.new(RubyLLM::Schema) }

      it "requests structured output and returns the parsed Hash" do
        adapter = described_class.new(client: mock_chat)
        result = adapter.extract(document: document, prompt: prompt, schema: schema)

        expect(mock_chat).to have_received(:with_schema).with(schema)
        expect(result).to eq("result" => "some data")
      end

      it "wraps schema errors as Kyc::Inference::Error" do
        allow(mock_chat).to receive(:with_schema).and_raise(RubyLLM::Error, "invalid schema")

        adapter = described_class.new(client: mock_chat)

        expect { adapter.extract(document: document, prompt: prompt, schema: schema) }
          .to raise_error(Kyc::Inference::Error, "invalid schema")
      end
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

    it "strips a markdown code fence before parsing (MH-172)" do
      fenced_response = instance_double(RubyLLM::Message, content: "```json\n{\"result\":\"some data\"}\n```")
      allow(mock_chat).to receive(:ask).and_return(fenced_response)

      adapter = described_class.new(client: mock_chat)
      result = adapter.generate(prompt: "Reply with JSON.")

      expect(result).to eq("result" => "some data")
    end

    context "when a schema is provided" do
      let(:schema) { Class.new(RubyLLM::Schema) }

      it "requests structured output and returns the parsed Hash" do
        adapter = described_class.new(client: mock_chat)
        result = adapter.generate(prompt: "Reply with JSON.", schema: schema)

        expect(mock_chat).to have_received(:with_schema).with(schema)
        expect(result).to eq("result" => "some data")
      end

      it "wraps schema errors as Kyc::Inference::Error" do
        allow(mock_chat).to receive(:with_schema).and_raise(RubyLLM::Error, "invalid schema")

        adapter = described_class.new(client: mock_chat)

        expect { adapter.generate(prompt: "Reply with JSON.", schema: schema) }
          .to raise_error(Kyc::Inference::Error, "invalid schema")
      end
    end
  end
end
