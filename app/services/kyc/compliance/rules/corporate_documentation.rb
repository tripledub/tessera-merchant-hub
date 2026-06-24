# frozen_string_literal: true

module Kyc
  module Compliance
    module Rules
      class CorporateDocumentation < BaseRule
        REQUIRED_DOC_TYPES = %w[certificate_of_incorporation].freeze

        def applies_to?(entity)
          entity.corporate?
        end

        def evaluate(entity)
          return not_applicable(entity) unless applies_to?(entity)

          doc_types = entity.linked_documents.pluck(:document_type).compact
          satisfied = REQUIRED_DOC_TYPES.select { |t| doc_types.include?(t) }

          build_result(entity: entity, requirements: REQUIRED_DOC_TYPES, satisfied: satisfied)
        end
      end
    end
  end
end
