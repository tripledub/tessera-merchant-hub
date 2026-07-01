# frozen_string_literal: true

module ExtractionData
  module Concerns
    module AddressProviding
      def person_full_name
        raise NotImplementedError, "#{self.class} must implement #person_full_name"
      end

      def structured_address
        raise NotImplementedError, "#{self.class} must implement #structured_address"
      end

      def to_matcher_hash
        { "full_name" => person_full_name, "date_of_birth" => nil }
      end
    end
  end
end
