# frozen_string_literal: true

module ExtractionData
  class CertificateOfDirectors < Base
    register_as :certificate_of_directors

    attribute :company_name, :string
    attribute :directors, :string
    attribute :issue_date, :date

    validates :company_name, presence: true
  end
end
