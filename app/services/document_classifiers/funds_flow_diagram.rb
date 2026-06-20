# frozen_string_literal: true

module DocumentClassifiers
  class FundsFlowDiagram < Base
    register handler: :funds_flow_diagram

    def self.pattern
      /funds?[\s_]*flow/i
    end
  end
end
