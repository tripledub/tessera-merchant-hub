# frozen_string_literal: true

module ExtractionData
  class ShareCertificate < Base
    register_as :share_certificate

    attribute :company_name, :string
    attribute :shareholder_name, :string
    attribute :number_of_shares, :string
    attribute :share_class, :string
    attribute :issue_date, :date
    attribute :certificate_number, :string

    validates :company_name, :shareholder_name, presence: true
  end
end
