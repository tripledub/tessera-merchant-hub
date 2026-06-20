# frozen_string_literal: true

module ExtractionData
  class CertificateOfRegisteredAddress < Base
    register_as :certificate_of_registered_address

    attribute :company_name, :string
    attribute :registered_address, :string
    attribute :issue_date, :date

    validates :company_name, :registered_address, presence: true
  end
end
