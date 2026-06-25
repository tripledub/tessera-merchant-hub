# frozen_string_literal: true

module Kyc
  class ExecutiveSummaryPresenter < BasePresenter
    include ContentTags

    presents :applicant

    # Ownership section
    def entity_count = data[:ownership][:entity_count]
    def individual_count = data[:ownership][:individual_count]
    def corporate_count = data[:ownership][:corporate_count]
    def jurisdictions = data[:ownership][:jurisdictions]

    # Edge summary
    def edge_count = data[:edges][:total]
    def equity_edge_count = data[:edges][:equity_count]
    def nominee_edge_count = data[:edges][:nominee_count]

    # UBOs
    def ubos = data[:ubos]
    def has_ubos? = ubos.any?

    # Warnings
    def warning_total = data[:warnings][:total]
    def warnings_by_type = data[:warnings][:by_type]
    def unacknowledged_warning_count = data[:warnings][:unacknowledged_count]

    # Documents
    def document_total = data[:documents][:total]
    def confirmed_document_count = data[:documents][:confirmed_count]
    def extracted_document_count = data[:documents][:extracted_count]
    def documents_by_type = data[:documents][:by_type]

    # Principals
    def principals = data[:principals]

    # Compliance
    def compliant? = data[:compliance][:compliant]
    def compliant_entity_count = data[:compliance][:compliant_entity_count]
    def compliance_entity_count = data[:compliance][:entity_count]
    def entity_results = data[:compliance][:entity_results]

    # Cross-references
    def cross_reference_discrepancies = data[:cross_references]
    def has_discrepancies? = cross_reference_discrepancies.any?

    # Narrative
    def has_narrative? = narrative.present?
    def executive_overview = narrative&.dig("executive_overview")
    def risk_factors = narrative&.dig("risk_factors") || []
    def recommended_actions = narrative&.dig("recommended_actions") || []
    def risk_assessment = narrative&.dig("risk_assessment")
    def narrative_generated_at = applicant.executive_narrative_generated_at

    # Badges
    def risk_assessment_badge
      case risk_assessment
      when "low" then badge("Low", :green)
      when "medium" then badge("Medium", :amber)
      when "high" then badge("High", :red)
      else badge("Not assessed", :gray)
      end
    end

    def compliance_status_badge
      compliant? ? badge("Compliant", :green) : badge("Not Compliant", :red)
    end

    private

    def data
      @data ||= ExecutiveSummary::DataAssembler.call(applicant)
    end

    def narrative
      @narrative ||= applicant.executive_narrative
    end
  end
end
