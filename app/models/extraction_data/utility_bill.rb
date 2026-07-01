# frozen_string_literal: true

module ExtractionData
  class UtilityBill < Base
    include Concerns::AddressProviding

    register_as :utility_bill

    attribute :full_name, :string
    attribute :account_holder_address_line1, :string
    attribute :account_holder_city, :string
    attribute :account_holder_postcode, :string
    attribute :account_holder_country, :string
    attribute :provider, :string
    attribute :provider_address, :string
    attribute :issue_date, :date
    attribute :account_number, :string

    def person_full_name
      full_name
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
