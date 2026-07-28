# frozen_string_literal: true

module Kyc
  module Compliance
    class ReadinessAssessment
      attr_reader :applicant, :entity_results

      def self.for(applicant)
        new(applicant)
      end

      def initialize(applicant)
        @applicant = applicant
        @entity_results = build_entity_results
      end

      def compliant?
        entity_results.all? { |er| er[:results].none?(&:blocks_automated_completion?) }
      end

      def entity_count
        entity_results.size
      end

      def compliant_entity_count
        entity_results.count { |er| er[:results].none?(&:blocks_automated_completion?) }
      end

      def all_results
        entity_results.flat_map { |er| er[:results] }
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
