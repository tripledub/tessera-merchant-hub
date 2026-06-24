# frozen_string_literal: true

module Kyc
  class CompliancePresenter < BasePresenter
    include ContentTags

    presents :applicant

    def warnings
      @warnings ||= applicant.validation_warnings.includes(:corporate_entity).order(acknowledged: :asc, created_at: :desc)
    end

    def has_warnings?
      warnings.any?
    end

    def total_count
      warnings.size
    end

    def unacknowledged_count
      warnings.count { |w| !w.acknowledged }
    end

    def count_by_type(type)
      warnings.count { |w| w.warning_type == type.to_s }
    end

    def warning_type_badge(warning)
      case warning.warning_type
      when "percentage_deviation"
        badge("% Deviation", :amber)
      when "nominee_detected"
        badge("Nominee", :red)
      when "unresolved_chain"
        badge("Unresolved", :amber)
      when "ubo_threshold_exceeded"
        badge("UBO", :blue)
      when "cross_reference_discrepancy"
        badge("Cross-ref", :red)
      end
    end

    def warning_icon_class(warning)
      case warning.warning_type
      when "percentage_deviation" then "text-amber-500"
      when "nominee_detected" then "text-red-500"
      when "unresolved_chain" then "text-amber-500"
      when "ubo_threshold_exceeded" then "text-blue-500"
      when "cross_reference_discrepancy" then "text-red-500"
      end
    end

    def warning_detail(warning)
      meta = warning.typed_metadata
      case warning.warning_type
      when "percentage_deviation"
        "Expected #{meta.expected}%, actual #{meta.actual}% (deviation: #{meta.deviation}%)"
      when "nominee_detected"
        parts = [ "Reason: #{meta.detection_reason.humanize}" ]
        parts << "Jurisdiction: #{meta.jurisdiction}" if meta.jurisdiction.present?
        parts.join(" · ")
      when "unresolved_chain"
        "Corporate entity with no traced individual owner"
      when "ubo_threshold_exceeded"
        "#{meta.effective_percentage}% effective ownership (threshold: #{meta.threshold}%)"
      when "cross_reference_discrepancy"
        parts = [ "Type: #{meta.discrepancy_type.humanize}" ]
        parts << "Chart: #{meta.chart_percentage}%" if meta.chart_percentage.present?
        parts << "Document: #{meta.document_percentage}%" if meta.document_percentage.present?
        parts << "Source: #{meta.document_name}" if meta.document_name.present?
        parts.join(" · ")
      end
    end
  end
end
