# frozen_string_literal: true

module Kyc
  module Inference
    class ClaudeAdapter < Base
      def initialize(client: nil)
        @client = client
      end

      def extract(document:, prompt:)
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
            { role: "user", content: [ content_block, { type: "text", text: prompt } ] }
          ]
        )

        parse_response(response)
      end

      def generate(prompt:)
        response = client.messages.create(
          model: "claude-sonnet-4-6",
          max_tokens: 4096,
          messages: [
            { role: "user", content: prompt }
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
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise Kyc::Inference::Error, "Claude returned invalid JSON: #{e.message}"
      end
    end
  end
end
