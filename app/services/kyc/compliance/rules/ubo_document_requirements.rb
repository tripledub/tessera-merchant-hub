# frozen_string_literal: true

module Kyc
  module Compliance
    module Rules
      class UboDocumentRequirements < BaseRule
        UBO_THRESHOLD = 25.0

        REQUIRED_CATEGORIES = {
          "identity" => Kyc::DocumentCategory.types_for(:identity),
          "proof_of_address" => Kyc::DocumentCategory.types_for(:proof_of_address)
        }.freeze

        def applies_to?(entity)
          return false unless entity.individual?

          Kyc::ValidationWarning.exists?(
            corporate_entity: entity,
            warning_type: :ubo_threshold_exceeded
          )
        end

        def evaluate(entity)
          return not_applicable(entity) unless applies_to?(entity)

          principal = find_matched_principal(entity)
          return build_result(entity: entity, requirements: requirement_names, satisfied: []) unless principal

          doc_types = principal.kyc_documents.pluck(:document_type).compact

          satisfied = []
          REQUIRED_CATEGORIES.each do |category, types|
            satisfied << category if types.any? { |t| doc_types.include?(t) }
          end

          build_result(entity: entity, requirements: requirement_names, satisfied: satisfied)
        end

        private

        def requirement_names
          REQUIRED_CATEGORIES.keys
        end

        def find_matched_principal(entity)
          entity.applicant.kyc_principals.find do |p|
            p.name.downcase.strip == entity.name.downcase.strip
          end
        end
      end
    end
  end
end
