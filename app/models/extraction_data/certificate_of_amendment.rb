# frozen_string_literal: true

module ExtractionData
  class CertificateOfAmendment < Base
    register_as :certificate_of_amendment

    attribute :company_name, :string
    attribute :amendment_date, :date
    attribute :registration_number, :string
    attribute :description, :string

    validates :company_name, presence: true
  end
end
