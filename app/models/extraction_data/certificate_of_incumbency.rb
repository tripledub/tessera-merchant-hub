# frozen_string_literal: true

module ExtractionData
  class CertificateOfIncumbency < Base
    register_as :certificate_of_incumbency

    attribute :company_name, :string
    attribute :directors, :string
    attribute :shareholders, :string
    attribute :registered_agent, :string
    attribute :registered_address, :string
    attribute :issue_date, :date

    validates :company_name, presence: true
  end
end
