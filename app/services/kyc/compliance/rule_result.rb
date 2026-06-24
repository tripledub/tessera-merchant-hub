# frozen_string_literal: true

module Kyc
  module Compliance
    RuleResult = Data.define(:rule_name, :entity, :status, :requirements, :satisfied, :missing) do
      def met?
        status == :met
      end

      def unmet?
        status == :unmet
      end

      def not_applicable?
        status == :not_applicable
      end
    end
  end
end
