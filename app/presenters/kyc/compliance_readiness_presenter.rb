# frozen_string_literal: true

module Kyc
  class ComplianceReadinessPresenter < BasePresenter
    include ContentTags

    presents :assessment

    def overall_status_badge
      badge(Compliance::ReadinessOutcome.label(outcome), Compliance::ReadinessOutcome.badge_colour(outcome))
    end

    # MH-200: the container styling around the badge/summary needs a third,
    # visually distinct treatment for "blocked only by confirmation_required
    # results" — amber/neutral, not the red used for an outright rejection
    # (unmet) and not the green used for fully compliant. MH-251 adds a fourth,
    # neutral grey for "not assessable": nothing has failed, nothing is known.
    def overall_status_container_class
      case outcome
      when :compliant
        "border-success-500 bg-success-50 dark:border-success-500/30 dark:bg-success-500/15"
      when :not_assessable
        "border-gray-300 bg-gray-50 dark:border-gray-700 dark:bg-white/[0.03]"
      when :requires_review
        "border-amber-500 bg-amber-50 dark:border-amber-500/30 dark:bg-amber-500/15"
      else
        "border-error-500 bg-error-50 dark:border-error-500/30 dark:bg-error-500/15"
      end
    end

    def outcome_message
      Compliance::ReadinessOutcome.description(outcome)
    end

    # MH-251: staff can confirm "no corporate owners" only while the ownership
    # graph is empty and nobody has confirmed it yet.
    def attestation_available?
      !applicant.no_corporate_owners_attested? && applicant.can_attest_no_corporate_owners?
    end

    def attestation_revocable?
      applicant.no_corporate_owners_attested?
    end

    def attestation_summary
      return unless applicant.no_corporate_owners_attested?

      I18n.t("applicants.tabs.overview.attested_by",
             name: applicant.no_corporate_owners_attested_by&.email || I18n.t("applicants.tabs.overview.former_staff_member"),
             date: applicant.no_corporate_owners_attested_at.strftime("%-d %b %Y"))
    end

    def entity_summary
      if assessment.entity_count.zero? && assessment.policy_results.any?
        return "#{pluralize(assessment.policy_results.size, "policy requirement")} evaluated"
      end

      "#{assessment.compliant_entity_count} of #{assessment.entity_count} entities compliant"
    end

    def rule_status_icon(result)
      case result.status
      when :met
        content_tag(:span, "✓", class: "text-success-500 font-bold")
      when :unmet
        content_tag(:span, "✗", class: "text-error-500 font-bold")
      else
        content_tag(:span, "—", class: "text-gray-400")
      end
    end

    def missing_summary
      missing = assessment.unmet_results
      return nil if missing.empty?

      missing.group_by { |result| result_subject(result) }.map do |subject, results|
        items = results.flat_map(&:missing)
        "#{subject}: #{items.map(&:humanize).join(', ')}"
      end
    end

    # MH-198 introduced confirmation_required_results as a status distinct
    # from unmet_results (data exists, but staff must confirm a date before
    # an automated outcome can be reached). MH-200 fixes the gap this left:
    # previously only unmet_results (missing_summary) was ever rendered, so
    # a confirmation_required result showed the same red "Not Compliant"
    # treatment as a rejection with no detail at all.
    def awaiting_confirmation_summary
      awaiting = assessment.confirmation_required_results
      return nil if awaiting.empty?

      awaiting.group_by { |result| result_subject(result) }.map do |subject, results|
        items = results.flat_map(&:awaiting_confirmation)
        "#{subject}: #{items.map(&:humanize).join(', ')}"
      end
    end

    private

    def result_subject(result)
      result.entity&.name || result.title
    end

    def outcome
      assessment.outcome
    end

    def applicant
      assessment.applicant
    end
  end
end
