# frozen_string_literal: true

module DocumentClassifiers
  class TransactionExtract < Base
    register handler: :transaction_extract

    def self.pattern
      /extract/i
    end
  end
end
