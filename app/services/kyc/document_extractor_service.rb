# frozen_string_literal: true

module Kyc
  class DocumentExtractorService
    class Error < StandardError; end

    # MH-306: mrz_line1/mrz_line2 (ExtractionData::Passport) need the model to
    # transcribe, not paraphrase — the generic "string or null" hint risks
    # normalized/cleaned-up output, which would silently break the
    # check-digit cross-check in Kyc::DocumentValidity::MrzExpiryConfidence.
    MRZ_HINT = "the exact machine-readable zone text near the bottom of the document, " \
      "character-for-character as printed including any < filler characters, or null if not visible"
    MRZ_FIELD_PATTERN = /\Amrz_line\d+\z/

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
    end

    def call
      schema = ExtractionData::Base.for(@document.document_type)
      prompt = build_prompt(schema)

      response = Kyc::Inference.adapter.extract(document: @document, prompt: prompt)
      raise Error, "Expected Hash response, got #{response.class}" unless response.is_a?(Hash)

      response
    rescue Kyc::Inference::Error => e
      raise Error, "Inference failed: #{e.message}"
    end

    private

    def build_prompt(schema)
      fields = schema.attribute_names.map do |attr|
        "\"#{attr}\": \"#{field_hint(attr, schema)}\""
      end

      return generic_prompt if fields.empty?

      build_field_prompt(fields)
    end

    def field_hint(attr, schema)
      return MRZ_HINT if attr.to_s.match?(MRZ_FIELD_PATTERN)

      case schema.attribute_types[attr].type
      when :date then "YYYY-MM-DD or null"
      when :boolean then "true or false"
      when :integer, :decimal, :float then "number or null"
      else "string or null"
      end
    end

    def build_field_prompt(fields)
      <<~PROMPT
        You are a KYC document analyst. Extract the following fields from this document.
        The document may be in any language — always return field values in English.

        Return ONLY valid JSON — no explanation, no markdown fences.

        Use this exact structure:
        {
          #{fields.join(",\n      ")}
        }

        Rules:
        - Preserve proper nouns (names, addresses) but transliterate to Latin script if needed
        - For dates, use YYYY-MM-DD format
        - Use null for any field you cannot find
        - Do not invent or guess values
        - If the document is not in English, translate descriptive text to English
      PROMPT
    end

    def generic_prompt
      <<~PROMPT
        You are a KYC document analyst. Extract all relevant information from this document.
        The document may be in any language — always return field values in English.

        Return ONLY valid JSON — no explanation, no markdown fences.

        Extract whatever fields are visible: names, dates, numbers, addresses, amounts,
        entities, and any other relevant data. Use descriptive key names.

        Rules:
        - Preserve proper nouns (names, addresses) but transliterate to Latin script if needed
        - For dates, use YYYY-MM-DD format
        - Use null for fields you cannot determine
        - Do not invent or guess values
        - If the document is not in English, translate descriptive text to English
      PROMPT
    end
  end
end
