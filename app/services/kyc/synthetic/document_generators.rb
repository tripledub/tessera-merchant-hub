# frozen_string_literal: true

module Kyc
  module Synthetic
    # MH-309: the extension point later document-type stories (utility bill,
    # certificate of incorporation, driving licence, share certificate)
    # implement against — each generator responds to
    # `.call(persona:, options:)` and returns raw PDF bytes. Adding a type
    # requires no change to Synthetic::Persona, only a new entry here.
    module DocumentGenerators
      REGISTRY = {
        "passport" => Kyc::Synthetic::PassportPdf
      }.freeze

      def self.types
        REGISTRY.keys
      end

      def self.for(document_type)
        REGISTRY.fetch(document_type.to_s) { raise ArgumentError, "unknown synthetic document type: #{document_type}" }
      end
    end
  end
end
