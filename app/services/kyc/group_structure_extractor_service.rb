# frozen_string_literal: true

module Kyc
  class GroupStructureExtractorService
    class ExtractionError < StandardError; end

    PROMPT = <<~PROMPT.freeze
      You are a KYC document analyst examining a corporate group structure chart.
      Extract every entity and ownership relationship visible in the chart.

      Return ONLY valid JSON — no explanation, no markdown fences.

      Use this exact structure:
      {
        "entities": [
          { "name": "Entity Name", "type": "corporate", "jurisdiction": "XX" }
        ],
        "edges": [
          { "parent": "Parent Name", "child": "Child Name", "relationship_type": "equity", "percentage": 50.0 }
        ]
      }

      Rules:
      - For type: use "individual" for natural persons, "corporate" for companies/entities
      - For jurisdiction: use ISO-2 country code if visible, or the jurisdiction text shown (e.g. "AU", "CY", "St Lucia"). Use null if not shown.
      - For relationship_type: use "equity" for direct ownership stakes, "nominee" when the chart labels an entity as a nominee or nominee shareholder, "contractual" for non-ownership relationships (e.g. payment agent agreement, service contract)
      - For percentage: the ownership percentage as a decimal (e.g. 61.76). Use null for contractual relationships.
      - List EVERY entity and EVERY edge visible in the chart. Do not omit any.
    PROMPT

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
      @applicant = document.applicant
    end

    def call
      raw = Kyc::Inference.adapter.extract(document: @document, prompt: PROMPT)
      response = normalize(raw)

      ActiveRecord::Base.transaction do
        Kyc::ValidationWarning.where(kyc_document: @document).delete_all
        Kyc::OwnershipEdge.where(source_document: @document).delete_all
        @document.corporate_entities.delete_all

        entity_map = create_entities(response[:entities])
        create_edges(response[:edges], entity_map)

        @document.update!(extracted_data: raw)

        Kyc::OwnershipPercentageValidator.call(@document)
        Kyc::NomineeDetector.call(@document)
      end
    end

    private

    def normalize(raw)
      {
        entities: raw.fetch("entities").map { |e| normalize_entity(e) },
        edges: raw.fetch("edges").map { |e| normalize_edge(e) }
      }
    rescue KeyError => e
      raise ExtractionError, "Response missing required key: #{e.message}"
    end

    def normalize_entity(raw)
      {
        name: raw.fetch("name"),
        type: raw.fetch("type"),
        jurisdiction: raw["jurisdiction"]
      }
    end

    def normalize_edge(raw)
      {
        parent: raw.fetch("parent"),
        child: raw.fetch("child"),
        relationship_type: raw.fetch("relationship_type"),
        percentage: raw["percentage"]&.to_f
      }
    end

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
