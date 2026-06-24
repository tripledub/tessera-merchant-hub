# frozen_string_literal: true

module Kyc
  module Compliance
    class RuleRegistry
      class << self
        def register(rule_class)
          rules << rule_class unless rules.include?(rule_class)
        end

        def all
          rules.dup
        end

        def reset!
          @rules = []
        end

        private

        def rules
          @rules ||= []
        end
      end
    end
  end
end
