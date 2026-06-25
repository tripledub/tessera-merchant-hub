# frozen_string_literal: true

module ExtractionData
  class UtilityBill < Base
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
  end
end
