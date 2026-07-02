# frozen_string_literal: true

module ExtractionData
  class CertificateOfRegisteredAddress < Base
    include Concerns::BusinessAddressProviding

    register_as :certificate_of_registered_address

    attribute :company_name, :string
    attribute :line1, :string
    attribute :city, :string
    attribute :postcode, :string
    attribute :country, :string
    attribute :issue_date, :date

    validates :company_name, :line1, presence: true

    def structured_address
      { line1: line1, city: city, postcode: postcode, country: country }
    end
  end
end
