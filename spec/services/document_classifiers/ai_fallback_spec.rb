# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentClassifiers::AiFallback do
  let(:document) { create(:kyc_document) }
  let(:condition) { DocumentClassifiers::Condition.new(filename: "unknown_doc.pdf", content_type: "application/pdf", document: document) }
  let(:handler) { described_class.new(condition) }

  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_context) { instance_double(RubyLLM::Context, chat: mock_chat) }

  before do
    allow(RubyLLM).to receive(:context).and_return(mock_context)
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

    context "when the attachment type is unsupported by the model" do
      before do
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::UnsupportedAttachmentError.new("application/x-not-a-real-format"))
      end

      it "raises an AiFallback::Error instead of propagating the RubyLLM error" do
        expect { handler.classify }.to raise_error(DocumentClassifiers::AiFallback::Error, /unsupported/i)
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

    # MH-233: xlsx/xls always resolve to RubyLLM's :document attachment type,
    # which the Anthropic provider's media formatter doesn't handle at all —
    # every such upload was guaranteed to raise RubyLLM::UnsupportedAttachmentError
    # after burning an API call and a worker slot. Reject before calling out.
    context "when the document's content type is not supported for AI classification" do
      let(:document) do
        create(:kyc_document).tap do |doc|
          doc.file.attach(io: StringIO.new("fake xlsx content"), filename: "export.xlsx",
                           content_type: "application/vnd.ms-excel")
        end
      end

      it "raises an AiFallback::Error without calling the AI model" do
        allow(mock_chat).to receive(:ask)

        expect { handler.classify }.to raise_error(DocumentClassifiers::AiFallback::Error, /not supported/i)
        expect(mock_chat).not_to have_received(:ask)
      end
    end

    context "when the AI request times out" do
      before do
        allow(mock_chat).to receive(:ask).and_raise(Faraday::TimeoutError.new("execution expired"))
      end

      it "raises an AiFallback::Error instead of propagating the timeout" do
        expect { handler.classify }.to raise_error(DocumentClassifiers::AiFallback::Error, /time(d)? out/i)
      end
    end
  end

  describe "request timeout" do
    it "scopes a request timeout to this chat call rather than the global RubyLLM config" do
      config = RubyLLM::Configuration.new
      allow(RubyLLM).to receive(:context).and_yield(config).and_return(mock_context)
      response = instance_double(RubyLLM::Message, content: '{"document_type": "passport", "confidence": 0.85}')
      allow(mock_chat).to receive(:ask).and_return(response)

      handler.classify

      expect(config.request_timeout).to eq(DocumentClassifiers::AiFallback::REQUEST_TIMEOUT)
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
