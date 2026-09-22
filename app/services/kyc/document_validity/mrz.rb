# frozen_string_literal: true

module Kyc
  module DocumentValidity
    # ICAO 9303 machine-readable-zone check-digit arithmetic (MH-306). Shared
    # by anything that needs to validate an MRZ field: weights 7/3/1 cycling
    # over the characters, digits at face value, letters as (ord - 'A'.ord)
    # + 10, and '<' filler as zero.
    module Mrz
      WEIGHTS = [ 7, 3, 1 ].freeze

      module_function

      def check_digit(text)
        total = text.each_char.with_index.sum do |ch, i|
          value_for(ch) * WEIGHTS[i % 3]
        end
        (total % 10).to_s
      end

      def value_for(ch)
        if ch.match?(/\d/)
          ch.to_i
        elsif ch.match?(/[A-Za-z]/)
          ch.upcase.ord - 55
        else
          0
        end
      end
      private_class_method :value_for
    end
  end
end
