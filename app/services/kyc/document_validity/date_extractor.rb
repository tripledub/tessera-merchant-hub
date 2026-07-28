# frozen_string_literal: true

module Kyc
  module DocumentValidity
    # Extracts issue/evidence and expiry dates for the abstract date "roles"
    # (e.g. "expiry", "issued") required by a document type's applicable
    # Kyc::DocumentValidityPolicy, and packages each one with its raw value,
    # normalized ISO8601 date, confidence, and extractor provenance.
    #
    # This service is read-only: it never persists anything. The caller
    # (ExtractKycDocumentJob) merges the returned hash into its own existing
    # `update!` call so validity data lands in the same write as the rest of
    # the extraction result.
    #
    # Confidence: the current Kyc::DocumentExtractorService prompt does not
    # ask the model for a per-field confidence score, so there is no
    # authoritative per-field signal available yet. To stay forward
    # compatible without requiring a prompt change, this service will prefer
    # a `"#{field}_confidence"` key on the raw extraction payload if present,
    # then fall back to the caller-supplied document-level `confidence:`,
    # then finally nil. A nil confidence is treated as NOT meeting the
    # acceptance threshold — i.e. it routes to staff confirmation rather than
    # being silently trusted. This is intentionally conservative: today, with
    # no real confidence signal, every required date will require staff
    # confirmation. That's expected until a confidence signal is wired up
    # (tracked separately) and is consistent with "route missing, malformed,
    # or low-confidence dates to staff confirmation".
    class DateExtractor
      # Matches the fuzzy-match acceptance threshold used elsewhere in the
      # KYC pipeline (see AddressMatcherService::FUZZY_THRESHOLD and the 0.80
      # cutoff in Onboarding::DocumentFeedbackService) so "good enough to
      # auto-accept" means the same thing across the app.
      CONFIDENCE_THRESHOLD = 0.80

      PROVENANCE = "ai_extraction"

      # Maps document_type -> { abstract date role => raw extraction field name }.
      # Only document types with a resolvable validity policy need an entry
      # here; document types outside the validity-policy rollout never reach
      # this map because .call returns inert before looking it up.
      FIELD_MAP = {
        "passport" => { "expiry" => "expiry_date" },
        "utility_bill" => { "issued" => "issue_date" }
      }.freeze

      INERT_RESULT = { validity_dates: {}, validity_confirmation_required: false }.freeze

      def self.call(document_type:, raw_extraction:, confidence: nil, reference_date: Date.current)
        new(document_type: document_type, raw_extraction: raw_extraction, confidence: confidence,
            reference_date: reference_date).call
      end

      def initialize(document_type:, raw_extraction:, confidence:, reference_date:)
        @document_type = document_type.to_s
        @raw_extraction = raw_extraction
        @document_confidence = confidence
        @reference_date = reference_date
      end

      def call
        return INERT_RESULT if @raw_extraction.blank?

        policy = Kyc::DocumentValidity::PolicyResolver.resolve(document_type: @document_type,
                                                                 reference_date: @reference_date)
        return INERT_RESULT if policy.nil?

        required_roles = Array(policy.required_dates)
        return INERT_RESULT if required_roles.empty?

        validity_dates = {}
        confirmation_required = false

        required_roles.each do |role|
          entry = extract_role(role)
          validity_dates[role] = entry
          confirmation_required ||= needs_confirmation?(entry)
        end

        { validity_dates: validity_dates, validity_confirmation_required: confirmation_required }
      end

      private

      def extract_role(role)
        field_name = FIELD_MAP.dig(@document_type, role)
        raw = field_name ? @raw_extraction[field_name] : nil
        raw = nil if raw.respond_to?(:blank?) && raw.blank?

        {
          raw: raw,
          normalized: normalize(raw),
          confidence: confidence_for(field_name),
          provenance: PROVENANCE
        }
      end

      def normalize(raw)
        return nil if raw.blank?

        Date.strptime(raw.to_s.strip, "%Y-%m-%d").iso8601
      rescue ArgumentError, Date::Error, TypeError
        nil
      end

      def confidence_for(field_name)
        return @document_confidence if field_name.nil?

        per_field_key = "#{field_name}_confidence"
        if @raw_extraction.key?(per_field_key)
          @raw_extraction[per_field_key]
        else
          @document_confidence
        end
      end

      def needs_confirmation?(entry)
        return true if entry[:normalized].nil?
        return true if entry[:confidence].nil?

        entry[:confidence] < CONFIDENCE_THRESHOLD
      end
    end
  end
end
