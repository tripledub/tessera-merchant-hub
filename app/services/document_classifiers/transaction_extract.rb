# frozen_string_literal: true

module DocumentClassifiers
  class TransactionExtract < Base
    register handler: :transaction_extract

    def self.pattern
      /transaction\s*extract|extract\s*[-–]\s*\d/i
    end
  end
end
