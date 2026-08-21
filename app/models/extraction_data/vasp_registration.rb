# frozen_string_literal: true

module ExtractionData
  class VaspRegistration < Base
    register_as :vasp_registration

    attribute :registration_number, :string
    attribute :registration_date, :date
    attribute :authorisation_number, :string
    attribute :authorisation_date, :date
  end
end
