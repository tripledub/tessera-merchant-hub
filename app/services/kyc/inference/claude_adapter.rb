# frozen_string_literal: true

module Kyc
  module Inference
    class ClaudeAdapter < Base
      PROMPT = <<~PROMPT.freeze
        You are a KYC document analyst examining a corporate group structure chart.
        Extract every entity and ownership relationship visible in the chart.

        Return ONLY valid JSON — no explanation, no markdown fences.

        Use this exact structure:
        {
          "entities": [
            { "name": "Entity Name", "type": "corporate", "jurisdiction": "XX" }
          ],
          "edges": [
            { "parent": "Parent Name", "child": "Child Name", "relationship_type": "equity", "percentage": 50.0 }
          ]
        }

        Rules:
        - For type: use "individual" for natural persons, "corporate" for companies/entities
        - For jurisdiction: use ISO-2 country code if visible, or the jurisdiction text shown (e.g. "AU", "CY", "St Lucia"). Use null if not shown.
        - For relationship_type: use "equity" for direct ownership stakes, "nominee" when the chart labels an entity as a nominee or nominee shareholder, "contractual" for non-ownership relationships (e.g. payment agent agreement, service contract)
        - For percentage: the ownership percentage as a decimal (e.g. 61.76). Use null for contractual relationships.
        - List EVERY entity and EVERY edge visible in the chart. Do not omit any.
      PROMPT

      def extract_group_structure(document)
        blob_data = document.file.blob.download
        base64    = Base64.strict_encode64(blob_data)
        mime_type = document.file.content_type

        content_block = if mime_type == "application/pdf"
          { type: "document", source: { type: "base64", media_type: "application/pdf", data: base64 } }
        else
          { type: "image", source: { type: "base64", media_type: mime_type, data: base64 } }
        end

        response = client.messages.create(
          model: "claude-sonnet-4-6",
          max_tokens: 4096,
          messages: [
            { role: "user", content: [ content_block, { type: "text", text: PROMPT } ] }
          ]
        )

        parse_response(response)
      end

      private

      def client
        @client ||= Anthropic::Client.new(api_key: api_key)
      end

      def api_key
        Rails.application.credentials.anthropic_api_key ||
          raise(Kyc::Inference::Error, "anthropic_api_key not set in Rails credentials")
      end

      def parse_response(response)
        text = response.content.first.text.strip
        raw  = JSON.parse(text)

        {
          entities: raw.fetch("entities").map { |e| normalize_entity(e) },
          edges: raw.fetch("edges").map { |e| normalize_edge(e) }
        }
      rescue JSON::ParserError => e
        raise Kyc::Inference::Error, "Claude returned invalid JSON: #{e.message}"
      rescue KeyError => e
        raise Kyc::Inference::Error, "Claude response missing required key: #{e.message}"
      end

      def normalize_entity(raw)
        {
          name: raw.fetch("name"),
          type: raw.fetch("type"),
          jurisdiction: raw["jurisdiction"]
        }
      end

      def normalize_edge(raw)
        {
          parent: raw.fetch("parent"),
          child: raw.fetch("child"),
          relationship_type: raw.fetch("relationship_type"),
          percentage: raw["percentage"]&.to_f
        }
      end
    end
  end
end
