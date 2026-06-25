# frozen_string_literal: true

module Kyc
  module ExecutiveSummary
    class DataAssembler
      def self.call(applicant)
        new(applicant).call
      end

      def initialize(applicant)
        @applicant = applicant
      end

      def call
        {
          ownership: ownership_section,
          edges: edges_section,
          ubos: ubos_section,
          warnings: warnings_section,
          documents: documents_section,
          principals: principals_section,
          compliance: compliance_section,
          cross_references: cross_references_section
        }
      end

      private

      attr_reader :applicant

      def ownership_section
        entities = applicant.corporate_entities
        {
          entity_count: entities.size,
          individual_count: entities.individual.size,
          corporate_count: entities.corporate.size,
          jurisdictions: entities.where.not(jurisdiction: nil).pluck(:jurisdiction).uniq
        }
      end

      def edges_section
        edges = Kyc::OwnershipEdge.where(parent_entity: applicant.corporate_entities)
        {
          total: edges.size,
          equity_count: edges.equity.size,
          nominee_count: edges.nominee.size,
          contractual_count: edges.contractual.size
        }
      end

      def ubos_section
        applicant.validation_warnings.ubo_threshold_exceeded.includes(:corporate_entity).map do |warning|
          meta = warning.typed_metadata
          {
            name: meta.respond_to?(:individual_name) ? meta.individual_name : warning.corporate_entity&.name,
            percentage: meta.respond_to?(:effective_percentage) ? meta.effective_percentage : nil,
            entity_id: warning.corporate_entity_id
          }
        end
      end

      def warnings_section
        warnings = applicant.validation_warnings
        by_type = warnings.group(:warning_type).count
        {
          total: warnings.size,
          acknowledged_count: warnings.where(acknowledged: true).size,
          unacknowledged_count: warnings.where(acknowledged: false).size,
          by_type: by_type
        }
      end

      def documents_section
        docs = applicant.kyc_documents
        {
          total: docs.size,
          confirmed_count: docs.classification_confirmed.size,
          extracted_count: docs.complete.size,
          by_type: docs.group(:document_type).count
        }
      end

      def principals_section
        applicant.kyc_principals.includes(:kyc_documents).map do |principal|
          {
            name: principal.name,
            principal_id: principal.id,
            linked_document_types: principal.kyc_documents.map(&:document_type).uniq
          }
        end
      end

      def compliance_section
        assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
        {
          compliant: assessment.compliant?,
          entity_count: assessment.entity_count,
          compliant_entity_count: assessment.compliant_entity_count,
          entity_results: assessment.entity_results.map do |er|
            {
              entity_name: er[:entity].name,
              entity_id: er[:entity].id,
              results: er[:results].map { |r| { rule: r.rule_name, met: r.met? } }
            }
          end
        }
      end

      def cross_references_section
        applicant.validation_warnings.cross_reference_discrepancy.includes(:corporate_entity).map do |warning|
          {
            entity_name: warning.corporate_entity&.name,
            message: warning.message
          }
        end
      end
    end
  end
end
