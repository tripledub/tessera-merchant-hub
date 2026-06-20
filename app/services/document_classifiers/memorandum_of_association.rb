# frozen_string_literal: true

module DocumentClassifiers
  class MemorandumOfAssociation < Base
    register handler: :memorandum_of_association

    def self.pattern
      /memorandum\s*(of\s*)?association/i
    end
  end
end
