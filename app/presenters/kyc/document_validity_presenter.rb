# frozen_string_literal: true

module Kyc
  # Staff-facing presentation of a KycDocument's current validity assessment
  # (MH-200). Wraps Kyc::DocumentValidity::Assessor.assess_or_reuse so the
  # displayed outcome always reflects the latest confirmed/extracted dates —
  # not a stale historical row — without appending a fresh assessment row on
  # every page load (assess_or_reuse only persists when something actually
  # changed; see MH-198).
  #
  # Exposes six distinct states: the five Kyc::DocumentValidityAssessment
  # outcomes, plus a sixth "no_assessment" state for a document type with no
  # resolvable Kyc::DocumentValidityPolicy at all (out of validity rollout).
  # These are deliberately never conflated — a document nobody has decided
  # to track is a different situation from one that has been tracked and
  # found wanting.
  class DocumentValidityPresenter < BasePresenter
    include ContentTags

    presents :document

    OUTCOME_BADGE_COLOURS = {
      "valid" => :green,
      "expiring_soon" => :amber,
      "expired" => :red,
      "stale" => :orange,
      "confirmation_required" => :blue,
      "no_assessment" => :gray
    }.freeze

    def assessment
      return @assessment if defined?(@assessment)

      @assessment = Kyc::DocumentValidity::Assessor.assess_or_reuse(
        document: document, reference_date: document.applicant.validity_reference_date
      )
    end

    def outcome_key
      assessment ? assessment.outcome : "no_assessment"
    end

    def outcome_label
      I18n.t("kyc.documents.validity.outcomes.#{outcome_key}")
    end

    def outcome_badge
      badge(outcome_label, OUTCOME_BADGE_COLOURS.fetch(outcome_key, :gray))
    end

    def policy_version
      assessment&.policy_version
    end

    # A plain-language sentence for the active assessment's machine
    # reason_code — staff should never need to read a raw reason_code like
    # "within_30_day_threshold" to understand why a document is in the
    # state it's in.
    def reason_text
      return nil unless assessment

      case assessment.reason_code
      when "within_validity_window"
        I18n.t("kyc.documents.validity.reasons.within_validity_window")
      when "past_printed_expiry"
        I18n.t("kyc.documents.validity.reasons.past_printed_expiry")
      when "older_than_max_age"
        I18n.t("kyc.documents.validity.reasons.older_than_max_age")
      when "missing_required_date"
        I18n.t("kyc.documents.validity.reasons.missing_required_date")
      when /\Awithin_(\d+)_day_threshold\z/
        within_day_threshold_text(Regexp.last_match(1))
      else
        I18n.t("kyc.documents.validity.reasons.unknown")
      end
    end

    def replacement_requirement
      @replacement_requirement ||= Kyc::DocumentReplacementRequirement.current_for(document)
    end

    def replacement_status_label
      return nil unless replacement_requirement

      I18n.t("kyc.documents.validity.replacement.status.#{replacement_requirement.status}")
    end

    # All Kyc::DocumentDateConfirmation rows for this document, across every
    # date role, most recent first — the read-only "history" view alongside
    # the per-role confirm/correct interaction MH-196 already built.
    def confirmation_history
      document.date_confirmations.order(created_at: :desc, id: :desc).to_a
    end

    # A plain-language description of what a single Kyc::DocumentDateConfirmation
    # row actually did to the value, distinguishing three cases a staff member
    # reviewing the audit trail needs to tell apart:
    #
    # - a plain confirmation of a value that was already extracted and left
    #   unchanged (extracted_value == confirmed_value)
    # - a correction, where the confirmed value differs from what was
    #   originally extracted — the original value must remain visible so staff
    #   can see what it was corrected FROM, not just what it is now
    # - a date entered from scratch where nothing was extracted at all
    #   (extracted_value nil — the MH-196 "missing date" scenario), which is
    #   neither a confirmation nor a correction of an existing value
    def confirmation_change_text(entry)
      if entry.extracted_value.nil?
        I18n.t("kyc.documents.validity.confirmation_history.change_entered",
               value: l(entry.confirmed_value))
      elsif entry.extracted_value == entry.confirmed_value
        I18n.t("kyc.documents.validity.confirmation_history.change_confirmed",
               value: l(entry.confirmed_value))
      else
        I18n.t("kyc.documents.validity.confirmation_history.change_corrected",
               original: l(entry.extracted_value), value: l(entry.confirmed_value))
      end
    end

    private

    def within_day_threshold_text(threshold)
      days_remaining = assessment.reason_details && assessment.reason_details["days_remaining"]
      I18n.t("kyc.documents.validity.reasons.within_day_threshold", threshold: threshold,
             days_remaining: days_remaining)
    end
  end
end
