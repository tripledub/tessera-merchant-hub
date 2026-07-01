# frozen_string_literal: true

module ExtractionData
  module Concerns
    module Identifiable
      def person_full_name
        raise NotImplementedError, "#{self.class} must implement #person_full_name"
      end

      def person_date_of_birth
        raise NotImplementedError, "#{self.class} must implement #person_date_of_birth"
      end

      def to_matcher_hash
        { "full_name" => person_full_name, "date_of_birth" => person_date_of_birth }
      end
    end
  end
end
