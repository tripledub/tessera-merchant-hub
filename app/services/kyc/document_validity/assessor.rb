# frozen_string_literal: true

module Kyc
  module DocumentValidity
    # Assesses a document against the Kyc::DocumentValidityPolicy applicable
    # at a given reference date, and persists the result as a new, immutable
    # Kyc::DocumentValidityAssessment historical record (MH-197).
    #
    # This service never updates an existing assessment: every call appends
    # a new row, so reassessing a document never loses the decision history
    # behind an earlier outcome. Callers who need "the current state" should
    # use Kyc::DocumentValidityAssessment.current_for(document).
    #
    # Authoritative date resolution (per required role): a staff
    # confirmation (Kyc::DocumentDateConfirmation.current_for) always wins
    # when present, regardless of the underlying extraction's confidence.
    # Otherwise, the extracted value is used only if it is present AND its
    # confidence meets Kyc::DocumentValidity::DateExtractor::CONFIDENCE_THRESHOLD.
    # If neither is available, the role has no authoritative date and the
    # assessment outcome is `confirmation_required`.
    #
    # Calendar arithmetic uses plain Date objects throughout (never Time),
    # so it is immune to DST entirely; only the caller's resolution of
    # `reference_date` (typically via Date.current) is timezone-sensitive.
    class Assessor
      CONFIDENCE_THRESHOLD = Kyc::DocumentValidity::DateExtractor::CONFIDENCE_THRESHOLD

      def self.call(document:, reference_date: Date.current)
        new(document: document, reference_date: reference_date).call
      end

      def initialize(document:, reference_date:)
        @document = document
        @reference_date = reference_date
      end

      def call
        policy = Kyc::DocumentValidity::PolicyResolver.resolve(document_type: @document.document_type,
                                                                 reference_date: @reference_date)
        return nil if policy.nil?

        resolution = resolve_dates(policy)

        outcome, reason_code, reason_details = if resolution[:missing_role]
          [ :confirmation_required, "missing_required_date", nil ]
        else
          evaluate(policy, resolution[:dates_used])
        end

        Kyc::DocumentValidityAssessment.create!(
          kyc_document: @document,
          kyc_document_validity_policy: policy,
          policy_version: policy.version,
          assessed_at: Time.current,
          reference_date: @reference_date,
          dates_used: resolution[:dates_used],
          outcome: outcome,
          reason_code: reason_code,
          reason_details: reason_details
        )
      end

      private

      # Determines the authoritative date for each role the policy requires.
      # Returns { dates_used:, missing_role: } where dates_used only contains
      # entries for roles that DO have an authoritative date (a role missing
      # an authoritative date is simply absent, and missing_role is set).
      def resolve_dates(policy)
        dates_used = {}
        missing_role = false

        Array(policy.required_dates).each do |role|
          confirmation = Kyc::DocumentDateConfirmation.current_for(@document, role)

          if confirmation
            dates_used[role] = { "date" => confirmation.confirmed_value.iso8601, "source" => "confirmed" }
            next
          end

          entry = @document.validity_dates[role]
          if entry.present? && entry["normalized"].present? && sufficiently_confident?(entry["confidence"])
            dates_used[role] = { "date" => entry["normalized"], "source" => "extracted" }
          else
            missing_role = true
          end
        end

        { dates_used: dates_used, missing_role: missing_role }
      end

      def sufficiently_confident?(confidence)
        confidence.present? && confidence >= CONFIDENCE_THRESHOLD
      end

      def evaluate(policy, dates_used)
        if policy.mode == "expires"
          evaluate_expires(policy, dates_used)
        else
          evaluate_freshness(policy, dates_used)
        end
      end

      def evaluate_expires(policy, dates_used)
        expiry_date = Date.iso8601(dates_used.fetch("expiry").fetch("date"))

        return [ :expired, "past_printed_expiry", nil ] if @reference_date > expiry_date

        days_remaining = expiry_date - @reference_date

        threshold = Array(policy.warning_thresholds).sort.find { |days| days_remaining <= days }
        return [ :valid, "within_validity_window", nil ] if threshold.nil?

        [ :expiring_soon, "within_#{threshold}_day_threshold",
          { "threshold_days" => threshold, "days_remaining" => days_remaining.to_i } ]
      end

      def evaluate_freshness(policy, dates_used)
        issued_date = Date.iso8601(dates_used.fetch("issued").fetch("date"))
        cutoff = @reference_date - policy.max_age_months.months

        return [ :stale, "older_than_max_age", nil ] if issued_date < cutoff

        [ :valid, "within_validity_window", nil ]
      end
    end
  end
end
