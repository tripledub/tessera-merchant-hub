# frozen_string_literal: true

module Kyc
  module Compliance
    class ReadinessAssessment
      # MH-251: precedence runs from the least to the most reassuring reading.
      OUTCOMES = %i[non_compliant not_assessable requires_review compliant].freeze

      attr_reader :applicant, :entity_results, :policy_results

      def self.for(applicant)
        new(applicant)
      end

      def initialize(applicant)
        @applicant = applicant
        # Applicant-level requirements: sector policy documents, plus any UBO
        # that has not been captured as an ownership entity.
        @policy_results = PolicyDocumentRequirements.evaluate(applicant) + UboEntityCoverage.evaluate(applicant)
        @entity_results = build_entity_results
      end

      # MH-251: readiness is one of OUTCOMES. Absence of evidence is never
      # compliance, so an empty ownership graph is :not_assessable unless staff
      # attested there are no corporate owners.
      def outcome
        @outcome ||=
          if blocking_unmet?
            :non_compliant
          elsif ownership_not_assessable?
            :not_assessable
          elsif requires_review?
            :requires_review
          else
            :compliant
          end
      end

      def compliant?
        outcome == :compliant
      end

      def entity_count
        entity_results.size
      end

      def compliant_entity_count
        entity_results.count { |er| er[:results].none?(&:blocks_automated_completion?) }
      end

      def all_results
        policy_results + entity_results.flat_map { |er| er[:results] }
      end

      def result_count
        all_results.size
      end

      def results_for(entity)
        er = entity_results.find { |e| e[:entity] == entity }
        er ? er[:results] : []
      end

      def unmet_results
        all_results.select(&:unmet?)
      end

      # MH-198: kept distinct from unmet_results so callers (e.g. MH-200's
      # UI) can label these as "awaiting staff review" rather than rejected,
      # even though both block automated completion (compliant?).
      def confirmation_required_results
        all_results.select(&:confirmation_required?)
      end

      private

      def blocking_unmet?
        all_results.any? { |result| result.unmet? && result.blocks_automated_completion? }
      end

      def ownership_not_assessable?
        entity_results.empty? && !applicant.no_corporate_owners_attested?
      end

      def requires_review?
        all_results.any? { |result| result.confirmation_required? && result.blocks_automated_completion? } ||
          applicant.validation_warnings.unresolved_chain.unacknowledged.exists?
      end

      def build_entity_results
        applicant.corporate_entities.map do |entity|
          {
            entity: entity,
            results: RuleRunner.evaluate_entity(entity)
          }
        end
      end
    end
  end
end
