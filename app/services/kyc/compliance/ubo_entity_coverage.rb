# frozen_string_literal: true

module Kyc
  module Compliance
    # MH-251: a UBO flagged from registry data carries no ownership entity, so
    # the per-entity rules never see it and readiness could stay green with a
    # 25%+ owner unaccounted for. Each such UBO must be captured as an ownership
    # entity (matched by name); until then it is an unmet blocking requirement.
    # Once captured, UboDocumentRequirements takes over for the evidence.
    class UboEntityCoverage
      MISSING = "ownership_entity"

      def self.evaluate(applicant)
        new(applicant).evaluate
      end

      def self.normalise(name)
        name.to_s.squish.downcase
      end

      def self.registry_ubo_warnings(applicant)
        applicant.validation_warnings.ubo_threshold_exceeded.where(corporate_entity_id: nil)
      end

      def self.registry_ubo?(applicant, name)
        registry_ubo_warnings(applicant).any? { |warning| normalise(ubo_name(warning)) == normalise(name) }
      end

      def self.ubo_name(warning)
        warning.metadata&.dig("individual_name")
      end

      def initialize(applicant)
        @applicant = applicant
      end

      def evaluate
        uncaptured = self.class.registry_ubo_warnings(@applicant).reject do |warning|
          entity_names.include?(self.class.normalise(self.class.ubo_name(warning)))
        end

        uncaptured.map { |warning| unmet_result(warning) }
      end

      private

      def entity_names
        @entity_names ||= @applicant.corporate_entities.pluck(:name).map { |name| self.class.normalise(name) }
      end

      def unmet_result(warning)
        RuleResult.new(
          rule_name: self.class.name.demodulize.underscore.humanize,
          entity: nil,
          status: :unmet,
          requirements: [ MISSING ],
          satisfied: [],
          missing: [ MISSING ],
          title: I18n.t("kyc.compliance.ubo_entity_coverage.title", name: self.class.ubo_name(warning).presence || warning.message),
          guidance: I18n.t("kyc.compliance.ubo_entity_coverage.guidance")
        )
      end
    end
  end
end
