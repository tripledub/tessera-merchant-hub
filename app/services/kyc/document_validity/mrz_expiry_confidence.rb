# frozen_string_literal: true

module Kyc
  module DocumentValidity
    # MH-306: computes a verifiable confidence signal for a passport's
    # printed expiry date by cross-checking it against the machine-readable
    # zone (MRZ), rather than trusting the model's own self-assessment (which
    # DateExtractor's header comment already flags as unavailable/unreliable).
    #
    # Auto-accepted (expiry_date_confidence 1.0, at DateExtractor::CONFIDENCE_THRESHOLD
    # or above) only when BOTH hold:
    #   - the MRZ's own expiry check digit is internally valid (the MRZ
    #     itself isn't corrupted or garbled in transcription)
    #   - the MRZ's expiry date matches the separately-extracted printed
    #     expiry_date exactly
    #
    # Anything else — no MRZ, wrong length, invalid check digit, disagreeing
    # date, missing/unparseable printed date, or a document type with no MRZ
    # role — adds no confidence key at all, so DateExtractor's existing
    # nil-confidence path is unchanged: the date still routes to staff
    # confirmation, exactly like every document type before this ticket.
    #
    # Called once, in ExtractKycDocumentJob, between DocumentExtractorService
    # and DateExtractor — DateExtractor itself needs no change, since it
    # already prefers a "<field>_confidence" key on the raw extraction hash.
    class MrzExpiryConfidence
      MRZ_DOCUMENT_TYPES = %w[passport].freeze
      LINE2_LENGTH = 44
      EXPIRY_RANGE = 21..26
      EXPIRY_CHECK_INDEX = 27
      AUTO_ACCEPT_CONFIDENCE = 1.0

      def self.enrich(...) = new(...).enrich

      def initialize(document_type:, raw_extraction:)
        @document_type = document_type.to_s
        @raw_extraction = raw_extraction
      end

      def enrich
        return @raw_extraction unless MRZ_DOCUMENT_TYPES.include?(@document_type)
        return @raw_extraction unless agrees?

        @raw_extraction.merge("expiry_date_confidence" => AUTO_ACCEPT_CONFIDENCE)
      end

      private

      def agrees?
        line2.present? && line2.length == LINE2_LENGTH && check_digit_valid? && mrz_expiry_matches_printed?
      end

      def line2
        @line2 ||= @raw_extraction["mrz_line2"].to_s.strip.upcase.presence
      end

      def expiry_field
        line2[EXPIRY_RANGE]
      end

      def check_digit_valid?
        Mrz.check_digit(expiry_field) == line2[EXPIRY_CHECK_INDEX]
      end

      def mrz_expiry_matches_printed?
        printed = printed_expiry
        printed.present? && expiry_field == printed.strftime("%y%m%d")
      end

      def printed_expiry
        raw = @raw_extraction["expiry_date"]
        return nil if raw.blank?

        Date.strptime(raw.to_s.strip, "%Y-%m-%d")
      rescue ArgumentError, Date::Error, TypeError
        nil
      end
    end
  end
end
