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

      def build_result(entity:, requirements:, satisfied:, awaiting_confirmation: [], requirement_id: nil,
                       title: nil, guidance: nil, outcome: :blocking)
        missing = requirements - satisfied - awaiting_confirmation
        status = if missing.any?
          :unmet
        elsif awaiting_confirmation.any?
          :confirmation_required
        else
          :met
        end

        RuleResult.new(
          rule_name: self.class.rule_name,
          entity: entity,
          status: status,
          requirements: requirements,
          satisfied: satisfied,
          missing: missing,
          awaiting_confirmation: awaiting_confirmation,
          requirement_id: requirement_id,
          title: title,
          guidance: guidance,
          outcome: outcome
        )
      end

      def not_applicable(entity, requirement_id: nil, title: nil, guidance: nil, outcome: :blocking)
        RuleResult.new(
          rule_name: self.class.rule_name,
          entity: entity,
          status: :not_applicable,
          requirements: [],
          satisfied: [],
          missing: [],
          awaiting_confirmation: [],
          requirement_id: requirement_id,
          title: title,
          guidance: guidance,
          outcome: outcome
        )
      end
    end
  end
end
