# frozen_string_literal: true

module Kyc
  module DocumentCategory
    REGISTRY = {
      identity:         %w[passport driving_licence],
      proof_of_address: %w[utility_bill bank_account_statement]
    }.freeze

    module_function

    def for(document_type)
      REGISTRY.find { |_, types| types.include?(document_type.to_s) }&.first
    end

    def identity?(document_type)
      self.for(document_type) == :identity
    end

    def proof_of_address?(document_type)
      self.for(document_type) == :proof_of_address
    end

    def types_for(category)
      REGISTRY.fetch(category.to_sym, [])
    end
  end
end
