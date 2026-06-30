# frozen_string_literal: true

module Kyc
  class CompletenessCalculator
    Dimension = Data.define(:key, :label, :numerator, :denominator) do
      def percentage
        return 0.0 if denominator.zero?

        (numerator.to_f / denominator * 100).round(1)
      end
    end

    WEIGHTS = {
      classification: 0.20,
      extraction: 0.20,
      identity_verification: 0.20,
      compliance_rules: 0.20,
      ownership_resolution: 0.20
    }.freeze

    attr_reader :applicant, :dimensions

    def self.for(applicant)
      new(applicant)
    end

    def initialize(applicant)
      @applicant = applicant
      @dimensions = build_dimensions
    end

    def overall_percentage
      active = dimensions.reject { |d| d.denominator.zero? }
      return 0.0 if active.empty?

      total_weight = active.sum { |d| WEIGHTS[d.key] }
      active.sum { |d| (WEIGHTS[d.key] / total_weight) * d.percentage }.round(1)
    end

    def as_chart_json
      {
        overall: overall_percentage,
        dimensions: dimensions.map do |d|
          { key: d.key, label: d.label, percentage: d.percentage,
            numerator: d.numerator, denominator: d.denominator }
        end
      }
    end

    private

    def build_dimensions
      [
        classification_dimension,
        extraction_dimension,
        identity_verification_dimension,
        compliance_rules_dimension,
        ownership_resolution_dimension
      ]
    end

    def classification_dimension
      docs = applicant.kyc_documents
      total = docs.count
      confirmed = docs.where(classification_status: :confirmed).count

      Dimension.new(key: :classification, label: "Classification",
                    numerator: confirmed, denominator: total)
    end

    def extraction_dimension
      confirmed_docs = applicant.kyc_documents.where(classification_status: :confirmed)
      total = confirmed_docs.count
      extracted = confirmed_docs.where(status: :complete).count

      Dimension.new(key: :extraction, label: "Extraction",
                    numerator: extracted, denominator: total)
    end

    def identity_verification_dimension
      principals = applicant.kyc_principals
      total = principals.count
      identity_types = KycDocument.document_types.values_at(*Kyc::DocumentCategory.types_for(:identity)).compact
      with_identity = principals.joins(:kyc_documents)
                                .where(kyc_documents: { document_type: identity_types })
                                .distinct.count

      Dimension.new(key: :identity_verification, label: "Identity Verification",
                    numerator: with_identity, denominator: total)
    end

    def compliance_rules_dimension
      assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
      results = assessment.all_results
      total = results.size
      met = results.count(&:met?)

      Dimension.new(key: :compliance_rules, label: "Compliance Rules",
                    numerator: met, denominator: total)
    end

    def ownership_resolution_dimension
      entities = applicant.corporate_entities
      total = entities.count
      unresolved_ids = applicant.validation_warnings
                                .where(warning_type: :unresolved_chain)
                                .select(:corporate_entity_id)
      resolved = entities.where.not(id: unresolved_ids).count

      Dimension.new(key: :ownership_resolution, label: "Ownership Resolution",
                    numerator: resolved, denominator: total)
    end
  end
end
