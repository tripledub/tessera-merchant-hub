# frozen_string_literal: true

module Kyc
  class NomineeDetector
    NOMINEE_JURISDICTIONS = %w[CY VG SC KY BZ PA MU].to_set.freeze
    NOMINEE_NAME_PATTERN = /nominee/i

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
      @applicant = document.applicant
    end

    def call
      detect_nominee_edges
      detect_nominee_jurisdictions
      detect_nominee_names
    end

    private

    def detect_nominee_edges
      Kyc::OwnershipEdge
        .joins(:parent_entity)
        .where(source_document: @document, relationship_type: :nominee)
        .find_each do |edge|
          create_warning(
            entity: edge.parent_entity,
            reason: "nominee_edge",
            message: "Nominee detected: #{edge.parent_entity.name} — nominee edge to #{edge.child_entity.name}"
          )
        end
    end

    def detect_nominee_jurisdictions
      entities.where(entity_type: :corporate).find_each do |entity|
        next unless NOMINEE_JURISDICTIONS.include?(entity.jurisdiction)

        create_warning(
          entity: entity,
          reason: "nominee_jurisdiction",
          jurisdiction: entity.jurisdiction,
          message: "Nominee detected: #{entity.name} — registered in #{entity.jurisdiction}"
        )
      end
    end

    def detect_nominee_names
      entities.find_each do |entity|
        next unless entity.name.match?(NOMINEE_NAME_PATTERN)

        create_warning(
          entity: entity,
          reason: "nominee_name",
          message: "Nominee detected: #{entity.name} — name contains 'nominee'"
        )
      end
    end

    def entities
      Kyc::CorporateEntity.where(kyc_document: @document)
    end

    def create_warning(entity:, reason:, message:, jurisdiction: nil)
      Kyc::ValidationWarning.create!(
        applicant: @applicant,
        kyc_document: @document,
        corporate_entity: entity,
        warning_type: :nominee_detected,
        message: message,
        metadata: { detection_reason: reason, jurisdiction: jurisdiction }
      )
    end
  end
end
