# frozen_string_literal: true

module Kyc
  module ExecutiveSummary
    class PdfGenerator
      DARK_COLOR = "333333"
      SECONDARY_COLOR = "666666"
      LIGHT_COLOR = "999999"
      HEADING_SIZE = 16
      BODY_SIZE = 10
      SMALL_SIZE = 8

      def self.call(applicant)
        new(applicant).call
      end

      def initialize(applicant)
        @applicant = applicant
        @data = DataAssembler.call(applicant)
        @narrative = applicant.executive_narrative
      end

      def call
        Prawn::Document.new(page_size: "A4", margin: [ 40, 40, 60, 40 ]) do |pdf|
          render_header(pdf)
          render_ownership_section(pdf)
          render_ubo_section(pdf)
          render_compliance_section(pdf)
          render_document_section(pdf)
          render_identity_section(pdf)
          render_warnings_section(pdf)
          render_cross_references_section(pdf)
          render_narrative_section(pdf) if @narrative.present?
          render_footer(pdf)
        end.render
      end

      private

      # --- Header ---

      def render_header(pdf)
        pdf.text "CONFIDENTIAL", size: SMALL_SIZE, color: "CC0000", align: :right
        pdf.move_down 4
        pdf.text "Due Diligence Executive Summary",
                 size: 22, style: :bold, color: DARK_COLOR
        pdf.move_down 6
        pdf.text @applicant.name, size: 14, style: :bold, color: DARK_COLOR
        pdf.move_down 4
        pdf.text "Generated #{Date.current.strftime('%d %B %Y')}",
                 size: BODY_SIZE, color: SECONDARY_COLOR
        pdf.stroke_horizontal_rule
        pdf.move_down 16
      end

      # --- Ownership ---

      def render_ownership_section(pdf)
        ownership = @data[:ownership]
        section_heading(pdf, "Ownership Overview")

        rows = [
          [ "Entities", ownership[:entity_count] ],
          [ "Individuals", ownership[:individual_count] ],
          [ "Corporates", ownership[:corporate_count] ],
          [ "Jurisdictions", ownership[:jurisdictions].join(", ") ]
        ]
        simple_table(pdf, rows)

        pdf.move_down 4
        pdf.text "Relationships: #{@data[:edges][:total]} total " \
                 "(#{@data[:edges][:equity_count]} equity, #{@data[:edges][:nominee_count]} nominee)",
                 size: BODY_SIZE, color: SECONDARY_COLOR
        pdf.move_down 16
      end

      # --- UBOs ---

      def render_ubo_section(pdf)
        ubos = @data[:ubos]
        return if ubos.empty?

        section_heading(pdf, "UBO Analysis")

        header = [ [ "Name", "Ownership %" ] ]
        rows = ubos.map { |u| [ u[:name], u[:percentage] ? "#{u[:percentage]}%" : "—" ] }
        pdf.table(header + rows, width: pdf.bounds.width, cell_style: { size: BODY_SIZE, padding: [ 4, 8 ] }) do |t|
          t.row(0).font_style = :bold
          t.row(0).background_color = "F0F0F0"
          t.cells.border_width = 0.5
          t.cells.border_color = "CCCCCC"
          t.columns(1).align = :right
        end
        pdf.move_down 16
      end

      # --- Compliance ---

      def render_compliance_section(pdf)
        compliance = @data[:compliance]
        section_heading(pdf, "Compliance Readiness")

        status = compliance[:compliant] ? "Compliant" : "Not Compliant"
        pdf.text "#{status} — #{compliance[:compliant_entity_count]} of #{compliance[:entity_count]} entities compliant",
                 size: BODY_SIZE, color: DARK_COLOR
        pdf.move_down 6

        compliance[:entity_results].each do |er|
          pdf.text er[:entity_name], size: BODY_SIZE, style: :bold, color: DARK_COLOR
          er[:results].each do |r|
            marker = r[:met] ? "✓" : "✗"
            pdf.text "  #{marker} #{r[:rule]}", size: BODY_SIZE, color: DARK_COLOR
          end
          pdf.move_down 4
        end
        pdf.move_down 12
      end

      # --- Documents ---

      def render_document_section(pdf)
        docs = @data[:documents]
        section_heading(pdf, "Document Status")

        rows = [
          [ "Total", docs[:total] ],
          [ "Confirmed", docs[:confirmed_count] ],
          [ "Extracted", docs[:extracted_count] ]
        ]
        simple_table(pdf, rows)

        if docs[:by_type].any?
          pdf.move_down 6
          pdf.text "By type: #{docs[:by_type].map { |t, c| "#{t.humanize} (#{c})" }.join(', ')}",
                   size: BODY_SIZE, color: SECONDARY_COLOR
        end
        pdf.move_down 16
      end

      # --- Identity Verification ---

      def render_identity_section(pdf)
        principals = @data[:principals]
        return if principals.empty?

        section_heading(pdf, "Identity Verification")

        principals.each do |p|
          linked = if p[:linked_document_types].any?
                     p[:linked_document_types].map(&:humanize).join(", ")
          else
                     "No documents linked"
          end
          pdf.text "#{p[:name]} — #{linked}", size: BODY_SIZE, color: DARK_COLOR
          pdf.move_down 3
        end
        pdf.move_down 12
      end

      # --- Warnings ---

      def render_warnings_section(pdf)
        warnings = @data[:warnings]
        section_heading(pdf, "Warnings")

        rows = [
          [ "Total", warnings[:total] ],
          [ "Open (unacknowledged)", warnings[:unacknowledged_count] ]
        ]
        simple_table(pdf, rows)

        if warnings[:by_type].any?
          pdf.move_down 6
          pdf.text "By type: #{warnings[:by_type].map { |t, c| "#{t.humanize} (#{c})" }.join(', ')}",
                   size: BODY_SIZE, color: SECONDARY_COLOR
        end
        pdf.move_down 16
      end

      # --- Cross-References ---

      def render_cross_references_section(pdf)
        discrepancies = @data[:cross_references]
        return if discrepancies.empty?

        section_heading(pdf, "Cross-Reference Discrepancies")

        discrepancies.each do |d|
          pdf.text d[:entity_name], size: BODY_SIZE, style: :bold, color: "CC0000"
          pdf.text d[:message], size: BODY_SIZE, color: DARK_COLOR
          pdf.move_down 4
        end
        pdf.move_down 12
      end

      # --- AI Narrative ---

      def render_narrative_section(pdf)
        section_heading(pdf, "AI Narrative")

        # Risk assessment
        risk = @narrative.dig("risk_assessment")
        if risk.present?
          pdf.text "Risk Assessment: #{risk.capitalize}",
                   size: BODY_SIZE, style: :bold, color: DARK_COLOR
          pdf.move_down 6
        end

        # Executive overview
        overview = @narrative.dig("executive_overview")
        if overview.present?
          pdf.text "Executive Overview", size: 12, style: :bold, color: DARK_COLOR
          pdf.move_down 4
          pdf.text overview, size: BODY_SIZE, color: DARK_COLOR
          pdf.move_down 8
        end

        # Risk factors
        factors = @narrative.dig("risk_factors") || []
        if factors.any?
          pdf.text "Risk Factors", size: 12, style: :bold, color: DARK_COLOR
          pdf.move_down 4
          factors.each do |rf|
            pdf.text "• #{rf}", size: BODY_SIZE, color: DARK_COLOR
          end
          pdf.move_down 8
        end

        # Recommended actions
        actions = @narrative.dig("recommended_actions") || []
        if actions.any?
          pdf.text "Recommended Actions", size: 12, style: :bold, color: DARK_COLOR
          pdf.move_down 4
          actions.each do |ra|
            pdf.text "→ #{ra}", size: BODY_SIZE, color: DARK_COLOR
          end
          pdf.move_down 8
        end

        pdf.move_down 8
      end

      # --- Footer ---

      def render_footer(pdf)
        pdf.repeat(:all) do
          pdf.bounding_box([ 0, pdf.bounds.bottom + 30 ], width: pdf.bounds.width, height: 20) do
            pdf.text "AI-assisted analysis — subject to human review",
                     size: SMALL_SIZE, color: LIGHT_COLOR, align: :left, valign: :center
          end
        end
        pdf.number_pages "<page> of <total>",
                         at: [ pdf.bounds.right - 60, pdf.bounds.bottom - 10 ],
                         size: SMALL_SIZE,
                         color: LIGHT_COLOR
      end

      # --- Helpers ---

      def section_heading(pdf, title)
        pdf.text title, size: HEADING_SIZE, style: :bold, color: DARK_COLOR
        pdf.move_down 8
      end

      def simple_table(pdf, rows)
        pdf.table(rows, width: pdf.bounds.width, cell_style: { size: BODY_SIZE, padding: [ 4, 8 ] }) do |t|
          t.cells.border_width = 0.5
          t.cells.border_color = "CCCCCC"
          t.columns(0).font_style = :bold
          t.columns(1).align = :right
        end
      end
    end
  end
end
