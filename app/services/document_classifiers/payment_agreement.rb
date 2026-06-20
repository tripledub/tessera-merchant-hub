# frozen_string_literal: true

module DocumentClassifiers
  class PaymentAgreement < Base
    register handler: :payment_agreement

    def self.pattern
      /payment\s*agreement/i
    end
  end
end
