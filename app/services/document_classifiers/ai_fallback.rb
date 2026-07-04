# frozen_string_literal: true

module DocumentClassifiers
  class AiFallback < Base
    class Error < StandardError; end

    VALID_TYPES = KycDocument.document_types.keys.freeze

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
        blob_data  = condition.document.file.blob.download
        media_type = condition.document.file.content_type
        extension  = Rack::Mime::MIME_TYPES.invert.fetch(media_type, ".bin").delete_prefix(".")
        prompt     = format(PROMPT, valid_types: VALID_TYPES.join(", ")) +
          "\n\nFilename (hint only): #{condition.filename}"

        response = Tempfile.create([ "kyc_classify", ".#{extension}" ]) do |f|
          f.binmode
          f.write(blob_data)
          f.flush
          chat.ask(prompt, with: f.path)
        end

        text = normalize_json_response(response.content)
        JSON.parse(text)
      rescue ActiveStorage::FileNotFoundError => e
        raise Error, "AI classifier could not read the document file: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "AI classifier returned invalid JSON: #{e.message}"
      rescue RubyLLM::Error => e
        raise Error, "AI classifier API error: #{e.message}"
      end
    end

    def chat
      @chat ||= RubyLLM.chat(model: "claude-haiku-4-5-20251001")
    end

    def normalize_json_response(text)
      stripped = text.strip
      stripped.match(/\A```(?:json)?\s*(.*?)\s*```\z/m)&.[](1) || stripped
    end
  end
end
