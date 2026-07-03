# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentClassifiers::AiFallback do
  let(:document) { create(:kyc_document) }
  let(:condition) { DocumentClassifiers::Condition.new(filename: "unknown_doc.pdf", content_type: "application/pdf", document: document) }
  let(:handler) { described_class.new(condition) }

  let(:mock_chat) { instance_double(RubyLLM::Chat) }

  before do
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
  end

  describe "#classify" do
    context "when AI returns a valid document type" do
      before do
        response = instance_double(RubyLLM::Message, content: '{"document_type": "passport", "confidence": 0.85}')
        allow(mock_chat).to receive(:ask).and_return(response)
      end

      it "returns the AI classification with confidence" do
        result = handler.classify
        expect(result).to eq(
          document_type: :passport,
          classification_method: :ai,
          confidence: 0.85
        )
      end

      it "sends the document file to the model as an attachment" do
        handler.classify
        expect(mock_chat).to have_received(:ask).with(anything, with: anything)
      end
    end

    context "when AI wraps JSON in a markdown fence" do
      before do
        response = instance_double(RubyLLM::Message, content: "```json\n{\"document_type\": \"passport\", \"confidence\": 0.85}\n```")
        allow(mock_chat).to receive(:ask).and_return(response)
      end

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
      before do
        response = instance_double(RubyLLM::Message, content: '{"document_type": null, "confidence": 0.0}')
        allow(mock_chat).to receive(:ask).and_return(response)
      end

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
      before do
        response = instance_double(RubyLLM::Message, content: '{"document_type": "spaceship_manual", "confidence": 0.5}')
        allow(mock_chat).to receive(:ask).and_return(response)
      end

      it "returns nil document type" do
        expect(handler.classify[:document_type]).to be_nil
      end
    end

    context "when AI returns invalid JSON" do
      before do
        response = instance_double(RubyLLM::Message, content: "not json at all")
        allow(mock_chat).to receive(:ask).and_return(response)
      end

      it "raises an error" do
        expect { handler.classify }.to raise_error(DocumentClassifiers::AiFallback::Error, /invalid JSON/)
      end
    end

    context "when API call fails" do
      before do
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new("server error"))
      end

      it "raises an error" do
        expect { handler.classify }.to raise_error(DocumentClassifiers::AiFallback::Error, /API error/)
      end
    end

    context "when the file blob cannot be downloaded" do
      before do
        allow(document.file.blob).to receive(:download).and_raise(ActiveStorage::FileNotFoundError)
      end

      it "raises an AiFallback::Error instead of propagating the storage error" do
        expect { handler.classify }.to raise_error(DocumentClassifiers::AiFallback::Error, /file/i)
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
    before do
      response = instance_double(RubyLLM::Message, content: '{"document_type": "legal_opinion", "confidence": 0.72}')
      allow(mock_chat).to receive(:ask).and_return(response)
    end

    it "is used when no rule-based handler matches" do
      result = DocumentClassifiers.obtain(condition)
      expect(result).to be_a(described_class)
      expect(result.classify[:document_type]).to eq(:legal_opinion)
      expect(result.classify[:classification_method]).to eq(:ai)
    end
  end
end
