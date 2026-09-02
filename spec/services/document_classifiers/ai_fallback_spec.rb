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

    context "when AI returns the routing-only processing statement type" do
      before do
        response = instance_double(RubyLLM::Message, content: '{"document_type": "processing_statement", "confidence": 0.9}')
        allow(mock_chat).to receive(:ask).and_return(response)
      end

      it "rejects the type for image and PDF classification" do
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

    context "when the document's content type is a spreadsheet MIME type" do
      it "classifies as a processing statement without calling the AI model" do
        allow(mock_chat).to receive(:ask)

        [
          [ "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "export.xlsx" ],
          [ "application/vnd.ms-excel", "export.xls" ],
          [ "text/csv", "export.csv" ]
        ].each do |content_type, filename|
          doc = create(:kyc_document).tap do |d|
            d.file.attach(io: StringIO.new("fake spreadsheet content"), filename: filename, content_type: content_type)
          end
          spreadsheet_handler = described_class.new(
            DocumentClassifiers::Condition.new(filename: filename, content_type: content_type, document: doc)
          )

          expect(spreadsheet_handler.classify).to eq(
            document_type: :processing_statement,
            classification_method: :spreadsheet_content_type,
            confidence: 0.0
          )
        end

        expect(mock_chat).not_to have_received(:ask)
      end
    end

    context "with every content type KycDocument accepts at upload time" do
      def classify_each_allowed_content_type
        called_for = []
        classified_without_ai = []

        KycDocument::ALLOWED_CONTENT_TYPES.each do |content_type|
          doc = create(:kyc_document).tap do |d|
            d.file.attach(io: StringIO.new("fake content"), filename: "upload.bin", content_type: content_type)
          end
          matrix_handler = described_class.new(
            DocumentClassifiers::Condition.new(filename: "upload.bin", content_type: content_type, document: doc)
          )

          result = matrix_handler.classify
          result[:classification_method] == :ai ? called_for << content_type : classified_without_ai << content_type
        end

        [ called_for, classified_without_ai ]
      end

      before do
        response = instance_double(RubyLLM::Message, content: '{"document_type": "passport", "confidence": 0.85}')
        allow(mock_chat).to receive(:ask).and_return(response)
      end

      it "calls the AI model only for non-spreadsheet supported types" do
        called_for, classified_without_ai = classify_each_allowed_content_type

        expect(called_for.sort).to eq(DocumentClassifiers::AiFallback::SUPPORTED_CONTENT_TYPES.sort)
        expect(classified_without_ai.sort).to eq(
          (KycDocument::ALLOWED_CONTENT_TYPES - DocumentClassifiers::AiFallback::SUPPORTED_CONTENT_TYPES).sort
        )
      end

      it "never calls the AI model for a content type classified as other" do
        called_for, = classify_each_allowed_content_type

        expect(mock_chat).to have_received(:ask).exactly(called_for.size).times
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
    # Exercises the real RubyLLM.context so mutating RubyLLM.config directly
    # (instead of the per-call context) would fail this. Needs a real (fake)
    # api key since RubyLLM.config.dup copies state, not RSpec stubs.
    around do |example|
      original_key = RubyLLM.config.anthropic_api_key
      RubyLLM.config.anthropic_api_key = "test-anthropic-key"
      example.run
      RubyLLM.config.anthropic_api_key = original_key
    end

    it "scopes a request timeout to this chat call without mutating the global RubyLLM config" do
      allow(RubyLLM).to receive(:context).and_call_original
      original_global_timeout = RubyLLM.config.request_timeout

      chat = handler.send(:chat)

      expect(chat.instance_variable_get(:@config).request_timeout)
        .to eq(DocumentClassifiers::AiFallback::REQUEST_TIMEOUT)
      expect(RubyLLM.config.request_timeout).to eq(original_global_timeout)
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
