# frozen_string_literal: true

module Kyc
  module Compliance
    module Rules
      class NomineeDocumentation < BaseRule
        REQUIRED_DOC_TYPES = %w[declaration_of_trust].freeze

        def applies_to?(entity)
          Kyc::ValidationWarning.exists?(
            corporate_entity: entity,
            warning_type: :nominee_detected
          )
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
