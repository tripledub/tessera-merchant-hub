# frozen_string_literal: true

module Kyc
  class DocumentExtractorService
    class Error < StandardError; end

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
        type = schema.attribute_types[attr].type
        format_hint = case type
        when :date then "YYYY-MM-DD or null"
        when :boolean then "true or false"
        when :integer, :decimal, :float then "number or null"
        else "string or null"
        end
        "\"#{attr}\": \"#{format_hint}\""
      end

      return generic_prompt if fields.empty?

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
