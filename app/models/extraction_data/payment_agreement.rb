# frozen_string_literal: true

module ExtractionData
  class PaymentAgreement < Base
    register_as :payment_agreement

    attribute :parties, :string
    attribute :effective_date, :date
    attribute :agreement_summary, :string

    validates :parties, presence: true
  end
end
