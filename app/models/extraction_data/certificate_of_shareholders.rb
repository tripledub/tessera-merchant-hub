# frozen_string_literal: true

module ExtractionData
  class CertificateOfShareholders < Base
    register_as :certificate_of_shareholders

    attribute :company_name, :string
    attribute :shareholders, :string
    attribute :issue_date, :date

    validates :company_name, presence: true
  end
end
