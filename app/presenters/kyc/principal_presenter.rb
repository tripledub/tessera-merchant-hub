# frozen_string_literal: true

module Kyc
  class PrincipalPresenter < BasePresenter
    presents :kyc_principal

    delegate :address_line1, :address_line2, :city, :postcode, :country, to: :kyc_principal

    def address_lines
      return [] unless address_present?

      lines = [ address_line1 ]
      lines << address_line2 if address_line2.present?
      lines << city_postcode
      lines << country
      lines
    end

    private

    def address_present?
      [ address_line1, city, postcode, country ].any?(&:present?)
    end

    def city_postcode
      [ city, postcode ].compact_blank.join(", ")
    end
  end
end
