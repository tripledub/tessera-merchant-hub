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
      Kyc::ValidationWarning.where(
        corporate_entity: @entity,
        warning_type: :cross_reference_discrepancy
      ).delete_all

      chart_edges = Kyc::OwnershipEdge.where(child_entity: @entity, relationship_type: :equity).includes(:parent_entity)
      return if chart_edges.empty?

      @chart_map = build_chart_map(chart_edges)

      @entity.linked_documents.each do |document|
        compare_document(document)
      end
    end

    private

    def build_chart_map(chart_edges)
      chart_edges.each_with_object({}) do |edge, map|
        map[edge.parent_entity.name.downcase.strip] = {
          name: edge.parent_entity.name,
          percentage: edge.percentage&.to_f
        }
      end
    end

    def compare_document(document)
      doc_map = extract_shareholders(document)
      return if doc_map.nil?

      check_document_against_chart(document, doc_map)
      check_chart_against_document(document, doc_map)
    rescue Kyc::Inference::Error => e
      Rails.logger.warn("CrossReferenceService: inference error for #{document.file.filename} — #{e.message}")
    end

    def extract_shareholders(document)
      raw = Kyc::Inference.adapter.extract(document: document, prompt: PROMPT)
      shareholders = raw.fetch("shareholders", [])
      return nil if shareholders.empty?

      shareholders.each_with_object({}) do |sh, map|
        map[sh["name"].to_s.downcase.strip] = {
          name: sh["name"],
          percentage: sh["percentage"]&.to_f
        }
      end
    end

    def check_document_against_chart(document, doc_map)
      doc_map.each do |key, doc_data|
        chart_match = find_match(key, @chart_map)

        if chart_match.nil?
          create_warning(
            document: document,
            discrepancy_type: "missing_from_chart",
            document_percentage: doc_data[:percentage],
            message: "#{doc_data[:name]} found in #{document.file.filename} but not in ownership chart"
          )
        elsif percentage_mismatch?(doc_data[:percentage], chart_match[:percentage])
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

    def check_chart_against_document(document, doc_map)
      @chart_map.each do |key, chart_data|
        next if find_match(key, doc_map)

        create_warning(
          document: document,
          discrepancy_type: "missing_from_document",
          chart_percentage: chart_data[:percentage],
          message: "#{chart_data[:name]} in ownership chart but not found in #{document.file.filename}"
        )
      end
    end

    def percentage_mismatch?(doc_pct, chart_pct)
      return false unless doc_pct && chart_pct

      (doc_pct - chart_pct).abs > PERCENTAGE_TOLERANCE
    end

    def find_match(key, map)
      return map[key] if map.key?(key)

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
