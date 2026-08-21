# frozen_string_literal: true

module Kyc
  module DocumentValidity
    class PolicyResolver
      def self.resolve(document_type:, reference_date: Date.current)
        return unless Kyc::PolicyRegistry.validity_applicable?(document_type)

        Kyc::DocumentValidityPolicy
          .where(document_type: document_type, enabled: true)
          .where("effective_from <= ?", reference_date)
          .order(version: :desc)
          .first
      end
    end
  end
end
