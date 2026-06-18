# frozen_string_literal: true

# DEV/TEST ONLY — never loaded in production (guarded below).
# Replaces the kynetic-ocr HTTP call with a direct Claude API call so the full
# KYC document upload → extraction → review journey can be exercised locally
# without running the kynetic-ocr service.
#
# Returns a hash in the same shape as kynetic-ocr's /process response so the
# rest of ProcessKycDocumentJob is unchanged.
#
# Enable with: CLAUDE_OCR=true bin/rails server
class ClaudeOcrAdapter
  class Error < StandardError; end

  PROMPT = <<~PROMPT.freeze
    You are a KYC document analyst. Extract the following fields from this document image.
    Return ONLY valid JSON with these exact keys — no explanation, no markdown, no code fences:

    {
      "document_type": "passport|driving_licence|utility_bill|bank_statement|other",
      "full_name": "Full name as it appears on the document, or null",
      "date_of_birth": "YYYY-MM-DD or null",
      "document_number": "Passport/licence number or null",
      "issuing_country": "ISO-2 country code or null",
      "issuing_authority": "Issuing authority or null",
      "expiry_date": "YYYY-MM-DD or null",
      "address": "Full address if present (utility bills etc.) or null"
    }
  PROMPT

  def self.process(document:)
    raise Error, "ClaudeOcrAdapter must not be used in production" if Rails.env.production?

    new(document).call
  end

  def initialize(document)
    @document = document
  end

  def call
    blob_data = @document.file.blob.download
    base64    = Base64.strict_encode64(blob_data)
    mime_type = @document.file.content_type

    client   = Anthropic::Client.new(api_key: api_key)
    response = client.messages.create(
      model:      "claude-opus-4-8",
      max_tokens: 1024,
      messages:   [
        {
          role:    "user",
          content: [
            { type: "image", source: { type: "base64", media_type: mime_type, data: base64 } },
            { type: "text",  text: PROMPT }
          ]
        }
      ]
    )

    text = response.content.first.text.strip
    JSON.parse(text)
  rescue JSON::ParserError => e
    raise Error, "Claude returned invalid JSON: #{e.message}"
  rescue Anthropic::Error => e
    raise Error, "Claude API error: #{e.message}"
  end

  private

  def api_key
    ENV.fetch("ANTHROPIC_API_KEY") { raise Error, "ANTHROPIC_API_KEY is not set" }
  end
end
