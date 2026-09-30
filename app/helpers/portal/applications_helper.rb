# frozen_string_literal: true

module Portal::ApplicationsHelper
  def format_review_address(address)
    return nil if address.nil?

    [ address.line1, address.line2, address.city, address.postcode, address.country ].compact_blank.join(", ")
  end
end
