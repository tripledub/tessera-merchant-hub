# frozen_string_literal: true

module Kyc
  module Synthetic
    # Builds the two 44-character TD3 machine-readable-zone lines for a
    # synthetic Utopia specimen passport (MH-309), with valid ICAO 9303 check
    # digits throughout.
    class PassportMrz
      DOCUMENT_CODE = "P"
      ISSUING_STATE = "UTO"
      LINE_LENGTH = 44
      PERSONAL_NUMBER = "<" * 14

      Result = Data.define(:line1, :line2)

      def self.call(persona:, document_number:, expiry_date:)
        new(persona: persona, document_number: document_number, expiry_date: expiry_date).call
      end

      def initialize(persona:, document_number:, expiry_date:)
        @persona = persona
        @document_number = document_number.to_s.upcase[0, 9].ljust(9, "<")
        @expiry_date = expiry_date
      end

      def call
        Result.new(line1: line1, line2: line2)
      end

      private

      def line1
        name_field = "#{transliterate(@persona.surname)}<<#{transliterate(@persona.given_names).gsub(' ', '<')}"
        "#{DOCUMENT_CODE}<#{ISSUING_STATE}#{name_field}".ljust(LINE_LENGTH, "<")[0, LINE_LENGTH]
      end

      def line2
        doc_check = Mrz.check_digit(@document_number)
        dob = @persona.date_of_birth.strftime("%y%m%d")
        dob_check = Mrz.check_digit(dob)
        expiry = @expiry_date.strftime("%y%m%d")
        expiry_check = Mrz.check_digit(expiry)
        personal_check = Mrz.check_digit(PERSONAL_NUMBER)
        composite = Mrz.check_digit(
          "#{@document_number}#{doc_check}#{dob}#{dob_check}#{expiry}#{expiry_check}#{PERSONAL_NUMBER}#{personal_check}"
        )

        "#{@document_number}#{doc_check}#{ISSUING_STATE}#{dob}#{dob_check}#{sex_code}" \
          "#{expiry}#{expiry_check}#{PERSONAL_NUMBER}#{personal_check}#{composite}"
      end

      def sex_code
        { "male" => "M", "female" => "F" }.fetch(@persona.sex, "<")
      end

      def transliterate(str)
        I18n.transliterate(str.to_s).upcase.gsub(/[^A-Z ]/, "")
      end
    end
  end
end
