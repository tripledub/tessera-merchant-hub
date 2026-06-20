# frozen_string_literal: true

module DocumentClassifiers
  class BusinessPlan < Base
    register handler: :business_plan

    def self.pattern
      /business\s*plan/i
    end
  end
end
