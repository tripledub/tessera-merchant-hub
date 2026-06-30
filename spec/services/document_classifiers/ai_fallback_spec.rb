# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentClassifiers::AiFallback do
  let(:condition) { DocumentClassifiers::Condition.new(filename: "unknown_doc.pdf", content_type: "application/pdf") }
  let(:handler) { described_class.new(condition) }

  let(:client) { instance_double(Anthropic::Client) }
  let(:messages) { instance_double(Anthropic::Resources::Messages) }

  before do
    allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return("test-key")
    allow(Anthropic::Client).to receive(:new).and_return(client)
    allow(client).to receive(:messages).and_return(messages)
  end

  describe "#classify" do
    context "when AI returns a valid document type" do
      let(:response) do
        instance_double(
          Anthropic::Models::Message,
          content: [ instance_double(Anthropic::Models::TextBlock, text: '{"document_type": "passport", "confidence": 0.85}') ]
        )
      end

      before { allow(messages).to receive(:create).and_return(response) }

      it "returns the AI classification with confidence" do
        result = handler.classify
        expect(result).to eq(
          document_type: :passport,
          classification_method: :ai,
          confidence: 0.85
        )
      end
    end

    context "when AI wraps JSON in a markdown fence" do
      let(:response) do
        instance_double(
          Anthropic::Models::Message,
          content: [
            instance_double(
              Anthropic::Models::TextBlock,
              text: "```json\n{\"document_type\": \"passport\", \"confidence\": 0.85}\n```"
            )
          ]
        )
      end

      before { allow(messages).to receive(:create).and_return(response) }

      it "returns the AI classification with confidence" do
        result = handler.classify
        expect(result).to eq(
          document_type: :passport,
          classification_method: :ai,
          confidence: 0.85
        )
      end
    end

    context "when AI returns null document type" do
      let(:response) do
        instance_double(
          Anthropic::Models::Message,
          content: [ instance_double(Anthropic::Models::TextBlock, text: '{"document_type": null, "confidence": 0.0}') ]
        )
      end

      before { allow(messages).to receive(:create).and_return(response) }

      it "returns nil document type" do
        result = handler.classify
        expect(result).to eq(
          document_type: nil,
          classification_method: :ai,
          confidence: 0.0
        )
      end
    end

    context "when AI returns an invalid document type" do
      let(:response) do
        instance_double(
          Anthropic::Models::Message,
          content: [ instance_double(Anthropic::Models::TextBlock, text: '{"document_type": "spaceship_manual", "confidence": 0.5}') ]
        )
      end

      before { allow(messages).to receive(:create).and_return(response) }

      it "returns nil document type" do
        expect(handler.classify[:document_type]).to be_nil
      end
    end

    context "when AI returns invalid JSON" do
      let(:response) do
        instance_double(
          Anthropic::Models::Message,
          content: [ instance_double(Anthropic::Models::TextBlock, text: "not json at all") ]
        )
      end

      before { allow(messages).to receive(:create).and_return(response) }

      it "raises an error" do
        expect { handler.classify }.to raise_error(DocumentClassifiers::AiFallback::Error, /invalid JSON/)
      end
    end

    context "when API call fails" do
      before do
        allow(messages).to receive(:create).and_raise(
          Anthropic::Errors::APIError.new(url: nil, status: 500, body: nil, message: "server error")
        )
      end

      it "raises an error" do
        expect { handler.classify }.to raise_error(DocumentClassifiers::AiFallback::Error, /API error/)
      end
    end
  end

  describe ".handles?" do
    it "always returns true" do
      expect(described_class.handles?(condition)).to be true
    end
  end

  describe "default registration" do
    it "is set as the default handler on DocumentClassifiers" do
      expect(DocumentClassifiers.default).to eq(described_class)
    end
  end

  describe "fallback via obtain" do
    let(:response) do
      instance_double(
        Anthropic::Models::Message,
        content: [ instance_double(Anthropic::Models::TextBlock, text: '{"document_type": "legal_opinion", "confidence": 0.72}') ]
      )
    end

    before { allow(messages).to receive(:create).and_return(response) }

    it "is used when no rule-based handler matches" do
      result = DocumentClassifiers.obtain(condition)
      expect(result).to be_a(described_class)
      expect(result.classify[:document_type]).to eq(:legal_opinion)
      expect(result.classify[:classification_method]).to eq(:ai)
    end
  end
end
