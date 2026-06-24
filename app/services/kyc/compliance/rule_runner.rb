# frozen_string_literal: true

module Kyc
  module Compliance
    class RuleRunner
      def self.evaluate_entity(entity)
        new.evaluate_entity(entity)
      end

      def self.evaluate_applicant(applicant)
        new.evaluate_applicant(applicant)
      end

      def evaluate_entity(entity)
        RuleRegistry.all.map do |rule_class|
          rule = rule_class.new
          if rule.applies_to?(entity)
            rule.evaluate(entity)
          else
            rule.send(:not_applicable, entity)
          end
        end
      end

      def evaluate_applicant(applicant)
        applicant.corporate_entities.flat_map do |entity|
          evaluate_entity(entity)
        end
      end
    end
  end
end
