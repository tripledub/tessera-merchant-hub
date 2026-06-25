# frozen_string_literal: true

module Kyc
  class CorporateEntityPresenter < BasePresenter
    include ContentTags

    presents :entity

    def entity_type_badge
      if entity.individual?
        badge("Individual", :blue)
      else
        badge("Corporate", :gray)
      end
    end

    def inbound_edges
      Kyc::OwnershipEdge.where(child_entity: entity).includes(:parent_entity, :source_document)
    end

    def outbound_edges
      Kyc::OwnershipEdge.where(parent_entity: entity).includes(:child_entity, :source_document)
    end

    def warnings
      Kyc::ValidationWarning.where(corporate_entity: entity).order(created_at: :desc)
    end

    def matched_principal
      return nil unless entity.individual?
      entity.applicant.kyc_principals.find { |p| p.name.downcase.strip == entity.name.downcase.strip }
    end

    def relationship_type_badge(edge)
      case edge.relationship_type
      when "equity" then badge("Equity", :green)
      when "nominee" then badge("Nominee", :amber)
      when "contractual" then badge("Contractual", :gray)
      end
    end

    def formatted_percentage(edge)
      return "—" if edge.percentage.nil?
      "#{edge.percentage}%"
    end

    def source_document_label(edge)
      return "—" unless edge.source_document

      edge.source_document.file.filename.to_s
    end

    def source_badge(record = entity)
      record.applicant_declared? ? badge("Declared", :amber) : badge("Extracted", :blue)
    end
  end
end
