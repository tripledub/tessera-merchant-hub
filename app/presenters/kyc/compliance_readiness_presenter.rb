# frozen_string_literal: true

module Kyc
  class ComplianceReadinessPresenter < BasePresenter
    include ContentTags

    presents :assessment

    def overall_status_badge
      if assessment.compliant?
        badge("Compliant", :green)
      elsif awaiting_confirmation_only?
        badge(I18n.t("applicants.tabs.overview.awaiting_review_badge"), :amber)
      else
        badge("Not Compliant", :red)
      end
    end

    # MH-200: the container styling around the badge/summary needs a third,
    # visually distinct treatment for "blocked only by confirmation_required
    # results" — amber/neutral, not the red used for an outright rejection
    # (unmet) and not the green used for fully compliant.
    def overall_status_container_class
      if assessment.compliant?
        "border-success-500 bg-success-50 dark:border-success-500/30 dark:bg-success-500/15"
      elsif awaiting_confirmation_only?
        "border-amber-500 bg-amber-50 dark:border-amber-500/30 dark:bg-amber-500/15"
      else
        "border-error-500 bg-error-50 dark:border-error-500/30 dark:bg-error-500/15"
      end
    end

    def entity_summary
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

    # True when every blocking result is confirmation_required — i.e.
    # nothing is outright unmet, so the overall picture is "awaiting staff
    # review", not "not compliant".
    def awaiting_confirmation_only?
      assessment.unmet_results.empty? && assessment.confirmation_required_results.any?
    end
  end
end
