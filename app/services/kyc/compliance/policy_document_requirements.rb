# frozen_string_literal: true

module Kyc
  module Compliance
    class PolicyDocumentRequirements
      def self.evaluate(applicant)
        requirements = Kyc::EffectivePolicy.for(applicant).select { |requirement| requirement.rule == "required_document" }
        current_document_types = applicant.kyc_documents.not_superseded.pluck(:document_type)

        requirements.map do |requirement|
          document_type = requirement.parameters.fetch("document_type")
          satisfied = current_document_types.include?(document_type)

          RuleResult.new(
            rule_name: requirement.rule.humanize,
            entity: nil,
            status: satisfied ? :met : :unmet,
            requirements: [ document_type ],
            satisfied: satisfied ? [ document_type ] : [],
            missing: satisfied ? [] : [ document_type ],
            requirement_id: requirement.id,
            title: requirement.title,
            guidance: requirement.guidance,
            outcome: requirement.outcome
          )
        end
      end
    end
  end
end
