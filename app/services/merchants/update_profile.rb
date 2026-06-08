# frozen_string_literal: true

module Merchants
  class UpdateProfile
    PERMITTED = %i[contact_email support_url address_line1 city country_code].freeze
    private_constant :PERMITTED

    def self.call(merchant, params) = new(merchant, params).call

    def initialize(merchant, params)
      @merchant = merchant
      @params   = params.to_h.symbolize_keys.slice(*PERMITTED)
    end

    def call
      @merchant.update(@params)
      @merchant
    end
  end
end
