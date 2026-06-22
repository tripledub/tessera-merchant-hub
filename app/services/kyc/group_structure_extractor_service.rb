# frozen_string_literal: true

module Kyc
  class GroupStructureExtractorService
    class ExtractionError < StandardError; end

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
      @applicant = document.applicant
    end

    def call
      response = Kyc::Inference.adapter.extract_group_structure(@document)

      ActiveRecord::Base.transaction do
        Kyc::OwnershipEdge.where(source_document: @document).delete_all
        @document.corporate_entities.delete_all

        entity_map = create_entities(response[:entities])
        create_edges(response[:edges], entity_map)

        @document.update!(extracted_data: response.deep_stringify_keys)
      end
    end

    private

    def create_entities(entities_data)
      entities_data.each_with_object({}) do |attrs, map|
        entity = Kyc::CorporateEntity.create!(
          applicant: @applicant,
          kyc_document: @document,
          name: attrs[:name],
          entity_type: attrs[:type],
          jurisdiction: attrs[:jurisdiction]
        )
        map[attrs[:name]] = entity
      end
    end

    def create_edges(edges_data, entity_map)
      edges_data.each do |attrs|
        parent = entity_map[attrs[:parent]]
        child  = entity_map[attrs[:child]]

        raise ExtractionError, "Entity not found: #{attrs[:parent]}" unless parent
        raise ExtractionError, "Entity not found: #{attrs[:child]}" unless child

        Kyc::OwnershipEdge.create!(
          parent_entity: parent,
          child_entity: child,
          relationship_type: attrs[:relationship_type],
          percentage: attrs[:percentage],
          source_document: @document
        )
      end
    end
  end
end
