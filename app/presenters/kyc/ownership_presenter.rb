# frozen_string_literal: true

module Kyc
  class OwnershipPresenter < BasePresenter
    include ContentTags

    presents :applicant

    def entities
      @entities ||= applicant.corporate_entities.order(:name)
    end

    def edges
      @edges ||= Kyc::OwnershipEdge
        .joins(:parent_entity, :child_entity)
        .where(parent_entity: { kyc_document_id: document_ids })
        .includes(:parent_entity, :child_entity)
        .order("kyc_corporate_entities.name")
    end

    def has_data?
      entities.any?
    end

    def entity_count
      entities.size
    end

    def edge_count
      edges.size
    end

    def individual_count
      entities.count { |e| e.individual? }
    end

    def corporate_count
      entities.count { |e| e.corporate? }
    end

    def entity_type_badge(entity)
      if entity.individual?
        badge("Individual", :blue)
      else
        badge("Corporate", :gray)
      end
    end

    def relationship_type_badge(edge)
      case edge.relationship_type
      when "equity"
        badge("Equity", :green)
      when "nominee"
        badge("Nominee", :amber)
      when "contractual"
        badge("Contractual", :gray)
      end
    end

    def formatted_percentage(edge)
      return "—" if edge.percentage.nil?

      "#{edge.percentage}%"
    end

    private

    def document_ids
      applicant.kyc_documents.pluck(:id)
    end
  end
end
