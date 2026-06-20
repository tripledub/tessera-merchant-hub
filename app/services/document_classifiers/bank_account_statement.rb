# frozen_string_literal: true

module DocumentClassifiers
  class BankAccountStatement < Base
    register handler: :bank_account_statement

    def self.pattern
      /bank\s*account\s*statement/i
    end
  end
end
