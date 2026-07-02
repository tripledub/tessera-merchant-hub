# frozen_string_literal: true

module ExtractionData
  class CertificateOfIncorporation < Base
    include Concerns::BusinessAddressProviding

    register_as :certificate_of_incorporation

    attribute :company_name, :string
    attribute :registration_number, :string
    attribute :date_of_incorporation, :date
    attribute :jurisdiction, :string
    attribute :line1, :string
    attribute :city, :string
    attribute :postcode, :string
    attribute :country, :string

    validates :company_name, :registration_number, presence: true

    def structured_address
      { line1: line1, city: city, postcode: postcode, country: country }
    end
  end
end
