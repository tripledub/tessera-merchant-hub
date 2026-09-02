# frozen_string_literal: true

module DocumentClassifiers
  class AiFallback < Base
    class Error < StandardError; end

    VALID_TYPES = KycDocument.document_types.keys.freeze

    SPREADSHEET_CONTENT_TYPES = %w[
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/vnd.ms-excel
      text/csv
    ].freeze

    # Spreadsheet uploads reaching this fallback have no matching filename
    # rule, so they belong to the processing-statement import flow instead of
    # being sent to the document AI classifier.
    SUPPORTED_CONTENT_TYPES = %w[
      image/jpeg image/png image/webp image/gif
      application/pdf
    ].freeze

    # Scoped per-call via RubyLLM.context, not the global RubyLLM.configure
    # shared with ClaudeOcrAdapter / Kyc::Inference::ClaudeAdapter.
    REQUEST_TIMEOUT = 30

    PROMPT = <<~PROMPT.freeze
      You are a KYC document classifier. Look at the attached document image or PDF and
      identify its document type. The filename is provided as a secondary hint only — do
      not rely on it if it conflicts with what you see in the document itself.
      Return ONLY valid JSON with these exact keys — no explanation, no markdown, no code
      fences:

      {
        "document_type": "one of: %{valid_types}",
        "confidence": 0.0 to 1.0
      }

      If you cannot determine the type from the document content, use null for
      document_type and 0.0 for confidence.
    PROMPT

    def self.handles?(_condition)
      true
    end

    def document_type
      result = ai_classify
      type = result["document_type"]
      return nil unless type && VALID_TYPES.include?(type)

      type.to_sym
    end

    def classification_method
      :ai
    end

    def classify
      media_type = condition.document.file.content_type

      if SPREADSHEET_CONTENT_TYPES.include?(media_type)
        return {
          document_type: :processing_statement,
          classification_method: :spreadsheet_content_type,
          confidence: 0.0
        }
      end

      unless SUPPORTED_CONTENT_TYPES.include?(media_type)
        return {
          document_type: :other,
          classification_method: :unsupported_content_type,
          confidence: 0.0
        }
      end

      result = ai_classify

      {
        document_type: document_type,
        classification_method: classification_method,
        confidence: result.fetch("confidence", 0.0).to_f
      }
    end

    private

    def ai_classify
      @ai_classify ||= begin
        blob_data = condition.document.file.blob.download
        extension = Rack::Mime::MIME_TYPES.invert.fetch(condition.document.file.content_type, ".bin").delete_prefix(".")
        prompt    = format(PROMPT, valid_types: VALID_TYPES.join(", ")) +
          "\n\nFilename (hint only): #{condition.filename}"

        response = Tempfile.create([ "kyc_classify", ".#{extension}" ]) do |f|
          f.binmode
          f.write(blob_data)
          f.flush
          chat.ask(prompt, with: f.path)
        end

        JSON.parse(Kyc::Inference::ResponseNormalizer.extract_json(response.content))
      rescue ActiveStorage::FileNotFoundError => e
        raise Error, "AI classifier could not read the document file: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "AI classifier returned invalid JSON: #{e.message}"
      rescue Faraday::TimeoutError => e
        raise Error, "AI classifier request timed out: #{e.message}"
      rescue RubyLLM::Error => e
        raise Error, "AI classifier API error: #{e.message}"
      rescue RubyLLM::UnsupportedAttachmentError => e
        raise Error, "AI classifier does not support this attachment type: #{e.message}"
      end
    end

    def chat
      @chat ||= RubyLLM.context { |config| config.request_timeout = REQUEST_TIMEOUT }
        .chat(model: "claude-haiku-4-5-20251001")
    end
  end
end
