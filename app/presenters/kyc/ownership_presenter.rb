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
        .includes(:parent_entity, :child_entity, :source_document)
        .order("kyc_corporate_entities.name")
    end

    def has_data?
      entities.any? || registry_pscs.any?
    end

    def registry_pscs
      @registry_pscs ||= begin
        profile = applicant.registry_profiles.last
        profile ? profile.people_with_significant_control.where(ceased_on: nil) : Registry::PersonWithSignificantControl.none
      end
    end

    def formatted_registry_percentage(psc)
      natures = Array(psc.natures_of_control)
      bands = natures.filter_map { |nature| nature[/\A(?:ownership-of-shares|voting-rights)-(\d+)-to-(\d+)-percent/, 1]&.to_i }
      return "#{bands.max}%+" if bands.any?
      return "—" if natures.empty?

      natures.map { |nature| nature.tr("-", " ").capitalize }.join(", ")
    end

    def registry_psc_kind_badge(psc)
      if psc.kind.start_with?("individual-")
        badge("Individual", :blue)
      else
        badge("Corporate", :gray)
      end
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

    def source_document_label(edge)
      return "—" unless edge.source_document

      edge.source_document.file.filename.to_s
    end

    def pie_chart_entity
      corporate_ids = entities.select(&:corporate?).map(&:id)
      target_id = edges.select { |e| corporate_ids.include?(e.child_entity_id) }
                       .group_by(&:child_entity_id)
                       .max_by { |_id, group| group.size }
                       &.first
      entities.find { |e| e.id == target_id }
    end

    def pie_chart_data(entity)
      pie_chart_edges(entity).each_with_index.map do |edge, i|
        {
          name: edge.parent_entity.name,
          percentage: edge.percentage&.to_f || 0,
          relationship_type: edge.relationship_type,
          index: i
        }
      end
    end

    def pie_chart_links(entity)
      pie_chart_edges(entity).map { |edge| kyc_corporate_entity_path(edge.parent_entity) }
    end

    private

    def pie_chart_edges(entity)
      edges.select { |e| e.child_entity_id == entity.id && %w[equity nominee].include?(e.relationship_type) }
    end

    def document_ids
      applicant.kyc_documents.pluck(:id)
    end
  end
end
