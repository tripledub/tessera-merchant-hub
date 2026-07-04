# frozen_string_literal: true

module Kyc
  module Inference
    class ClaudeAdapter < Base
      MODEL_ID = ENV.fetch("KYC_INFERENCE_MODEL", "claude-sonnet-4-6")

      def initialize(client: nil)
        @client = client
      end

      def extract(document:, prompt:, schema: nil)
        blob_data  = document.file.blob.download
        media_type = document.file.content_type
        extension  = Rack::Mime::MIME_TYPES.invert.fetch(media_type, ".bin").delete_prefix(".")

        result = Tempfile.create([ "kyc_doc", ".#{extension}" ]) do |f|
          f.binmode
          f.write(blob_data)
          f.flush
          build_chat(schema).ask(prompt, with: f.path)
        end

        parse_result(result)
      rescue RubyLLM::Error => e
        raise Kyc::Inference::Error, e.message
      end

      def generate(prompt:, schema: nil, stream: false, &block)
        if stream
          build_chat(schema).ask(prompt, &block)
        else
          parse_result(build_chat(schema).ask(prompt))
        end
      rescue RubyLLM::Error => e
        raise Kyc::Inference::Error, e.message
      end

      private

      def build_chat(schema)
        c = @client || RubyLLM.chat(model: MODEL_ID)
        schema ? c.with_schema(schema) : c
      end

      def parse_result(response)
        content = response.content
        return content if content.is_a?(Hash)

        JSON.parse(content)
      rescue JSON::ParserError => e
        raise Kyc::Inference::Error, "Claude returned invalid JSON: #{e.message}"
      end
    end
  end
end
