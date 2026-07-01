# frozen_string_literal: true

module ExtractionData
  class Passport < Base
    include Concerns::Identifiable

    register_as :passport

    attribute :full_name, :string
    attribute :date_of_birth, :date
    attribute :document_number, :string
    attribute :expiry_date, :date
    attribute :issuing_country, :string
    attribute :nationality, :string
    attribute :issuing_authority, :string

    validates :full_name, :document_number, :expiry_date, presence: true

    def person_full_name
      full_name
    end

    def person_date_of_birth
      date_of_birth
    end
  end
end
