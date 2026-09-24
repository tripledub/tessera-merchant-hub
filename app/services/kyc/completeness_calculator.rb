# frozen_string_literal: true

module Kyc
  class CompletenessCalculator
    Dimension = Data.define(:key, :label, :numerator, :denominator) do
      def percentage
        return 0.0 if denominator.zero?

        (numerator.to_f / denominator * 100).round(1)
      end
    end

    # Equal weighting across all six dimensions (sums to 1.0). Dimensions with
    # a zero denominator are dropped and the rest renormalised in
    # #overall_percentage, so an applicant with no domains scores as before.
    WEIGHTS = {
      classification: 1.0 / 6,
      extraction: 1.0 / 6,
      identity_verification: 1.0 / 6,
      compliance_rules: 1.0 / 6,
      ownership_resolution: 1.0 / 6,
      domain_review: 1.0 / 6
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
        ownership_resolution_dimension,
        domain_review_dimension
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
      # MH-199: superseded documents (replaced by a newer upload of the same
      # type after their replacement requirement was closed) are excluded —
      # they are historical artifacts, not part of the applicant's current
      # active document set, and counting them would understate completeness
      # once a valid replacement is on file.
      confirmed_docs = applicant.kyc_documents.not_superseded.where(classification_status: :confirmed)
      total = confirmed_docs.count
      extracted = confirmed_docs.where(status: :complete).select { |doc| extraction_satisfied?(doc) }.size

      Dimension.new(key: :extraction, label: "Extraction",
                    numerator: extracted, denominator: total)
    end

    # MH-198: a confirmed + extracted document only counts toward extraction
    # completeness if it is ALSO validity-acceptable. Documents whose type
    # has no resolvable policy (out of rollout) get a nil assessment back —
    # "no validity opinion" — and keep exactly their pre-MH-198 behaviour of
    # counting on status: :complete alone.
    def extraction_satisfied?(document)
      assessment = Kyc::DocumentValidity::Assessor.assess_or_reuse(
        document: document, reference_date: applicant.validity_reference_date
      )
      return true if assessment.nil?

      assessment.valid_outcome? || assessment.expiring_soon_outcome?
    end

    def identity_verification_dimension
      principals = applicant.kyc_principals.active
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

    # MH-297: domains extracted from proof-of-domain documents are pending until
    # a psp_admin accepts or rejects them, and until then the application isn't
    # complete. Hand-added domains are accepted on creation, so they count as
    # reviewed.
    def domain_review_dimension
      domains = applicant.applicant_domains
      reviewed = domains.where.not(review_status: :pending).count

      Dimension.new(key: :domain_review, label: "Domain Review",
                    numerator: reviewed, denominator: domains.count)
    end
  end
end
