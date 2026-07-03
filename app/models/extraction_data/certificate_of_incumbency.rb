# frozen_string_literal: true

module ExtractionData
  class CertificateOfIncumbency < Base
    include Concerns::BusinessAddressProviding

    register_as :certificate_of_incumbency

    attribute :company_name, :string
    attribute :directors, :string
    attribute :shareholders, :string
    attribute :registered_agent, :string
    attribute :line1, :string
    attribute :city, :string
    attribute :postcode, :string
    attribute :country, :string
    attribute :issue_date, :date

    validates :company_name, presence: true

    def structured_address
      { line1: line1, city: city, postcode: postcode, country: country }
    end
  end
end
