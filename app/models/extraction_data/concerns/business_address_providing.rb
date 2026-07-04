# frozen_string_literal: true

module ExtractionData
  module Concerns
    module BusinessAddressProviding
      def structured_address
        raise NotImplementedError, "#{self.class} must implement #structured_address"
      end
    end
  end
end
