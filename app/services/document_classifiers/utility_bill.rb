# frozen_string_literal: true

module DocumentClassifiers
  class UtilityBill < Base
    register handler: :utility_bill

    def self.pattern
      /utility\s*bill/i
    end
  end
end
