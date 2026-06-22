# frozen_string_literal: true

module Kyc
  class UnresolvedChainDetector
    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
      @applicant = document.applicant
    end

    def call
      corporate_entities.find_each do |entity|
        next if has_inbound_equity?(entity)

        Kyc::ValidationWarning.create!(
          applicant: @applicant,
          kyc_document: @document,
          corporate_entity: entity,
          warning_type: :unresolved_chain,
          message: "Unresolved ownership: #{entity.name} has no traced parent — further documentation required",
          metadata: { entity_name: entity.name }
        )
      end
    end

    private

    def corporate_entities
      Kyc::CorporateEntity.where(kyc_document: @document, entity_type: :corporate)
    end

    def has_inbound_equity?(entity)
      Kyc::OwnershipEdge.where(child_entity: entity, relationship_type: :equity).exists?
    end
  end
end
