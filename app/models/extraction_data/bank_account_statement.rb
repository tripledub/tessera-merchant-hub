# frozen_string_literal: true

module ExtractionData
  class BankAccountStatement < Base
    register_as :bank_account_statement

    attribute :account_holder, :string
    attribute :bank_name, :string
    attribute :account_number, :string
    attribute :sort_code, :string
    attribute :iban, :string
    attribute :currency, :string
    attribute :statement_period_start, :date
    attribute :statement_period_end, :date
    attribute :opening_balance, :string
    attribute :closing_balance, :string

    validates :account_holder, :bank_name, presence: true
  end
end
