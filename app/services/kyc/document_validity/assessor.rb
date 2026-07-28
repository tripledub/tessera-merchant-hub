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

      # MH-198: the entry point for callers (completeness/readiness) that run
      # on every request and must NOT append a new historical row just
      # because the page was reloaded. Since .call always persists, this
      # reuses Kyc::DocumentValidityAssessment.current_for(document) when the
      # resolved policy and the authoritative dates behind it are IDENTICAL
      # to what a fresh .call would resolve right now, and only calls
      # through to .call (creating a new row) when something has genuinely
      # changed: a new/updated confirmation or extraction, a newer policy
      # version, or the reference_date itself moving (e.g. a new
      # application/review cycle). With a stable reference_date, unchanged
      # inputs against an unchanged policy always produce an identical
      # outcome, so reassessing them would be redundant, not merely cheap
      # to skip.
      def self.assess_or_reuse(document:, reference_date:)
        policy = Kyc::DocumentValidity::PolicyResolver.resolve(document_type: document.document_type,
                                                                 reference_date: reference_date)
        return nil if policy.nil?

        current = Kyc::DocumentValidityAssessment.current_for(document)

        if current && reusable?(current, policy: policy, document: document, reference_date: reference_date)
          return current
        end

        call(document: document, reference_date: reference_date)
      end

      def self.reusable?(assessment, policy:, document:, reference_date:)
        return false unless assessment.reference_date == reference_date
        return false unless assessment.kyc_document_validity_policy_id == policy.id
        return false unless assessment.policy_version == policy.version

        assessment.dates_used == resolve_dates(document: document, policy: policy,
                                                 reference_date: reference_date)[:dates_used]
      end
      private_class_method :reusable?

      # Exposes the (otherwise private, per-instance) authoritative-date
      # resolution so .assess_or_reuse can compare "what dates_used would be
      # right now" against a prior assessment's snapshot without duplicating
      # the confirmed-beats-extracted-if-confident logic. resolve_dates
      # itself never reads @reference_date (only .evaluate does), so the
      # reference_date passed through here is unused today, but kept so this
      # stays correct if that ever changes.
      def self.resolve_dates(document:, policy:, reference_date: Date.current)
        new(document: document, reference_date: reference_date).send(:resolve_dates, policy)
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
