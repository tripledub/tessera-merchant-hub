# frozen_string_literal: true

module Kyc
  module Synthetic
    # ICAO 9303 machine-readable-zone check digit: each character is weighted
    # 7/3/1, repeating, and the check digit is the sum mod 10. Digits count as
    # themselves, letters A-Z count as 10-35, and the filler '<' (or any other
    # character) counts as 0.
    module Mrz
      WEIGHTS = [ 7, 3, 1 ].freeze

      module_function

      def check_digit(string)
        sum = string.each_char.each_with_index.sum { |char, i| char_value(char) * WEIGHTS[i % 3] }
        (sum % 10).to_s
      end

      def char_value(char)
        return char.to_i if char.match?(/\A\d\z/)
        return char.ord - "A".ord + 10 if char.match?(/\A[A-Z]\z/)

        0
      end
    end
  end
end
