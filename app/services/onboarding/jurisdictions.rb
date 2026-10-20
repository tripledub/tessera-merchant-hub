# frozen_string_literal: true

module Onboarding
  # MH-391: maps what an applicant says is their country onto a registry
  # jurisdiction (and back, to fill in the country when the PSP has already chosen
  # one). Only the countries we offer as chips.
  module Jurisdictions
    COUNTRY_BY_JURISDICTION = { "gb" => "United Kingdom", "mt" => "Malta", "cy" => "Cyprus", "xu" => "Utopia" }.freeze

    ALIASES = {
      "gb" => [ "united kingdom", "uk", "u.k.", "great britain", "gb", "england", "scotland", "wales", "northern ireland" ],
      "mt" => [ "malta", "mt" ],
      "cy" => [ "cyprus", "cy" ]
    }.freeze

    module_function

    # "gb", "mt", "cy" for a country we recognise; nil for anything else (Other).
    def jurisdiction_for(country)
      text = country.to_s.strip.downcase
      return if text.blank?

      ALIASES.find { |_jurisdiction, names| names.include?(text) }&.first
    end

    def country_for(jurisdiction)
      COUNTRY_BY_JURISDICTION[jurisdiction.to_s]
    end
  end
end
