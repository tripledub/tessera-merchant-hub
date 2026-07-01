# frozen_string_literal: true

module ExtractionData
  class BankAccountStatement < Base
    include Concerns::AddressProviding

    register_as :bank_account_statement

    attribute :account_holder, :string
    attribute :account_holder_address_line1, :string
    attribute :account_holder_city, :string
    attribute :account_holder_postcode, :string
    attribute :account_holder_country, :string
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

    def person_full_name
      account_holder
    end

    def structured_address
      {
        line1: account_holder_address_line1,
        city: account_holder_city,
        postcode: account_holder_postcode,
        country: account_holder_country
      }
    end
  end
end
