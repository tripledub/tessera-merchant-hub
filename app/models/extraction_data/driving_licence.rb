# frozen_string_literal: true

module ExtractionData
  class DrivingLicence < Base
    register_as :driving_licence

    attribute :full_name, :string
    attribute :date_of_birth, :date
    attribute :document_number, :string
    attribute :expiry_date, :date
    attribute :issuing_country, :string
    attribute :address, :string

    validates :full_name, :document_number, :expiry_date, presence: true
  end
end
