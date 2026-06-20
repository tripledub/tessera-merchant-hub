# frozen_string_literal: true

module ExtractionData
  class Passport < Base
    register_as :passport

    attribute :full_name, :string
    attribute :date_of_birth, :date
    attribute :document_number, :string
    attribute :expiry_date, :date
    attribute :issuing_country, :string
    attribute :nationality, :string
    attribute :issuing_authority, :string

    validates :full_name, :document_number, :expiry_date, presence: true
  end
end
