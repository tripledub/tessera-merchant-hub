# frozen_string_literal: true

module Kyc
  module Compliance
    class BaseRule
      def self.inherited(subclass)
        super
        RuleRegistry.register(subclass)
      end

      def self.rule_name
        name.demodulize.underscore.humanize
      end

      def applies_to?(entity)
        raise NotImplementedError, "#{self.class}#applies_to? must be implemented"
      end

      def evaluate(entity)
        raise NotImplementedError, "#{self.class}#evaluate must be implemented"
      end

      private

      def build_result(entity:, requirements:, satisfied:)
        missing = requirements - satisfied
        status = missing.empty? ? :met : :unmet

        RuleResult.new(
          rule_name: self.class.rule_name,
          entity: entity,
          status: status,
          requirements: requirements,
          satisfied: satisfied,
          missing: missing
        )
      end

      def not_applicable(entity)
        RuleResult.new(
          rule_name: self.class.rule_name,
          entity: entity,
          status: :not_applicable,
          requirements: [],
          satisfied: [],
          missing: []
        )
      end
    end
  end
end
