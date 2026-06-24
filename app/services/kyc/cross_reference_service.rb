# frozen_string_literal: true

module Kyc
  class CrossReferenceService
    PERCENTAGE_TOLERANCE = 0.5

    PROMPT = <<~PROMPT.freeze
      You are a KYC document analyst. Extract all ownership and shareholding information from this document.

      Return ONLY valid JSON — no explanation, no markdown fences.

      Use this exact structure:
      {
        "shareholders": [
          { "name": "Shareholder Name", "percentage": 50.0 }
        ]
      }

      Rules:
      - List every shareholder/member/beneficial owner mentioned in the document
      - For percentage: the ownership percentage as a decimal. If shares are given instead of percentages, calculate the percentage from total shares if possible. Use null if percentage cannot be determined.
      - Include all shareholders, even those with small holdings
    PROMPT

    def self.call(entity)
      new(entity).call
    end

    def initialize(entity)
      @entity = entity
      @applicant = entity.applicant
    end

    def call
      # Clear previous cross-reference warnings for this entity
      Kyc::ValidationWarning.where(
        corporate_entity: @entity,
        warning_type: :cross_reference_discrepancy
      ).delete_all

      chart_edges = Kyc::OwnershipEdge.where(child_entity: @entity, relationship_type: :equity).includes(:parent_entity)
      return if chart_edges.empty?

      @entity.linked_documents.each do |document|
        compare_document(document, chart_edges)
      end
    end

    private

    def compare_document(document, chart_edges)
      raw = Kyc::Inference.adapter.extract(document: document, prompt: PROMPT)
      shareholders = raw.fetch("shareholders", [])
      return if shareholders.empty?

      chart_map = chart_edges.each_with_object({}) do |edge, map|
        map[edge.parent_entity.name.downcase.strip] = {
          name: edge.parent_entity.name,
          percentage: edge.percentage&.to_f
        }
      end

      doc_map = shareholders.each_with_object({}) do |sh, map|
        map[sh["name"].to_s.downcase.strip] = {
          name: sh["name"],
          percentage: sh["percentage"]&.to_f
        }
      end

      # Check each document shareholder against chart
      doc_map.each do |key, doc_data|
        chart_match = find_match(key, chart_map)

        if chart_match.nil?
          create_warning(
            document: document,
            discrepancy_type: "missing_from_chart",
            document_percentage: doc_data[:percentage],
            chart_percentage: nil,
            message: "#{doc_data[:name]} found in #{document.file.filename} but not in ownership chart"
          )
        elsif doc_data[:percentage] && chart_match[:percentage]
          deviation = (doc_data[:percentage] - chart_match[:percentage]).abs
          if deviation > PERCENTAGE_TOLERANCE
            create_warning(
              document: document,
              discrepancy_type: "percentage_mismatch",
              document_percentage: doc_data[:percentage],
              chart_percentage: chart_match[:percentage],
              message: "#{doc_data[:name]}: chart shows #{chart_match[:percentage]}% but #{document.file.filename} shows #{doc_data[:percentage]}%"
            )
          end
        end
      end

      # Check chart edges not found in document
      chart_map.each do |key, chart_data|
        doc_match = find_match(key, doc_map)
        if doc_match.nil?
          create_warning(
            document: document,
            discrepancy_type: "missing_from_document",
            chart_percentage: chart_data[:percentage],
            document_percentage: nil,
            message: "#{chart_data[:name]} in ownership chart but not found in #{document.file.filename}"
          )
        end
      end
    rescue Kyc::Inference::Error => e
      Rails.logger.warn("CrossReferenceService: inference error for #{document.file.filename} — #{e.message}")
    end

    def find_match(key, map)
      # Exact match first
      return map[key] if map.key?(key)

      # Fuzzy match
      map.each do |candidate_key, data|
        score = JaroWinkler.similarity(key, candidate_key)
        return data if score >= 0.92
      end

      nil
    end

    def create_warning(document:, discrepancy_type:, message:, chart_percentage: nil, document_percentage: nil)
      Kyc::ValidationWarning.create!(
        applicant: @applicant,
        kyc_document: document,
        corporate_entity: @entity,
        warning_type: :cross_reference_discrepancy,
        message: message,
        metadata: {
          document_name: document.file.filename.to_s,
          chart_percentage: chart_percentage,
          document_percentage: document_percentage,
          discrepancy_type: discrepancy_type
        }
      )
    end
  end
end
