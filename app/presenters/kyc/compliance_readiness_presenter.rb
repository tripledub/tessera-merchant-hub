# frozen_string_literal: true

module Kyc
  class ComplianceReadinessPresenter < BasePresenter
    include ContentTags

    presents :assessment

    def overall_status_badge
      if assessment.compliant?
        badge("Compliant", :green)
      else
        badge("Not Compliant", :red)
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

      missing.group_by { |r| r.entity.name }.map do |entity_name, results|
        items = results.flat_map(&:missing)
        "#{entity_name}: #{items.map(&:humanize).join(', ')}"
      end
    end
  end
end
