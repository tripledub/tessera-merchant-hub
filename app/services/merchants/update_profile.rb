# frozen_string_literal: true

module Merchants
  class UpdateProfile
    include AttributeUpdater

    PERMITTED = %i[contact_email support_url address_line1 city country_code].freeze
    private_constant :PERMITTED
  end
end
