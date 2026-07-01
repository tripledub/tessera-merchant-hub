# frozen_string_literal: true

module ExtractionData
  class DrivingLicence < Base
    include Concerns::Identifiable

    register_as :driving_licence

    attribute :full_name, :string
    attribute :date_of_birth, :date
    attribute :document_number, :string
    attribute :expiry_date, :date
    attribute :issuing_country, :string
    attribute :address_line1, :string
    attribute :city, :string
    attribute :postcode, :string
    attribute :country, :string

    validates :full_name, :document_number, :expiry_date, presence: true

    def person_full_name
      full_name
    end

    def person_date_of_birth
      date_of_birth
    end
  end
end
