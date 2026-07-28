# frozen_string_literal: true

module Kyc
  module Compliance
    module Rules
      # MH-198: surfaces document-validity outcomes (MH-197) as readiness
      # requirements. A linked document type only counts as "satisfied" if
      # at least one document of that type is currently valid or
      # expiring_soon; expired/stale documents do not satisfy it (blocking,
      # :unmet). A document type where the only linked document(s) are
      # confirmation_required is reported as :confirmation_required — a
      # DISTINCT status from :unmet so callers can label it "awaiting staff
      # review" rather than an outright rejection, even though it still
      # blocks automated completion (see RuleResult#blocks_automated_completion?).
      #
      # Document types with no resolvable Kyc::DocumentValidityPolicy (out of
      # rollout) are excluded from `requirements` entirely, so entities whose
      # linked documents are all out-of-rollout types keep their pre-MH-198
      # behaviour exactly (this rule reports :not_applicable for them).
      class DocumentValidity < BaseRule
        def applies_to?(entity)
          covered_document_types(entity).any?
        end

        def evaluate(entity)
          return not_applicable(entity) unless applies_to?(entity)

          requirements = covered_document_types(entity)
          satisfied = []
          awaiting_confirmation = []

          requirements.each do |doc_type|
            outcomes = assess_documents_of_type(entity, doc_type)

            if outcomes.any? { |a| a.valid_outcome? || a.expiring_soon_outcome? }
              satisfied << doc_type
            elsif outcomes.any?(&:confirmation_required_outcome?)
              awaiting_confirmation << doc_type
            end
          end

          build_result(entity: entity, requirements: requirements, satisfied: satisfied,
                       awaiting_confirmation: awaiting_confirmation)
        end

        private

        # MH-199: superseded documents are excluded from both the set of
        # document types this rule covers and from the documents assessed
        # for each type — an old, replaced document must not keep an
        # already-closed requirement's document type "satisfied" (or
        # unsatisfied) once a valid replacement is on file.
        def covered_document_types(entity)
          entity.linked_documents.not_superseded.map(&:document_type).uniq.compact.select do |doc_type|
            Kyc::DocumentValidity::PolicyResolver.resolve(
              document_type: doc_type, reference_date: entity.applicant.validity_reference_date
            ).present?
          end
        end

        def assess_documents_of_type(entity, doc_type)
          entity.linked_documents.not_superseded.select { |d| d.document_type == doc_type }.filter_map do |document|
            Kyc::DocumentValidity::Assessor.assess_or_reuse(
              document: document, reference_date: entity.applicant.validity_reference_date
            )
          end
        end
      end
    end
  end
end
