# frozen_string_literal: true

module ExtractionData
  class UtilityBill < Base
    register_as :utility_bill

    attribute :full_name, :string
    attribute :address, :string
    attribute :provider, :string
    attribute :issue_date, :date
    attribute :account_number, :string

    validates :full_name, :address, presence: true
  end
end
