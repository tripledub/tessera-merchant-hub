# frozen_string_literal: true

module ExtractionData
  class CertificateOfIncorporation < Base
    register_as :certificate_of_incorporation

    attribute :company_name, :string
    attribute :registration_number, :string
    attribute :date_of_incorporation, :date
    attribute :jurisdiction, :string
    attribute :registered_address, :string

    validates :company_name, :registration_number, presence: true
  end
end
