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
    raise Error, "anthropic_api_key not set in Rails credentials" unless Rails.application.credentials.anthropic_api_key

    blob_data  = @document.file.blob.download
    media_type = @document.file.content_type
    extension  = Rack::Mime::MIME_TYPES.invert.fetch(media_type, ".bin").delete_prefix(".")

    result = Tempfile.create([ "kyc_ocr", ".#{extension}" ]) do |f|
      f.binmode
      f.write(blob_data)
      f.flush
      RubyLLM.chat(model: "claude-opus-4-8").ask(PROMPT, with: f.path)
    end

    JSON.parse(result.content)
  rescue JSON::ParserError => e
    raise Error, "Claude returned invalid JSON: #{e.message}"
  rescue RubyLLM::Error => e
    raise Error, "Claude API error: #{e.message}"
  end
end
