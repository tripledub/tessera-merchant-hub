# frozen_string_literal: true

module Kyc
  module Synthetic
    # MH-309: renders a synthetic Utopia specimen passport PDF for a
    # Synthetic::Persona. First implementation of the document-generator
    # interface (persona + type-specific options -> PDF bytes) later document
    # types implement against.
    #
    # Options:
    #   place_of_birth  — free text, required
    #   passport_number — up to 9 characters, required (also feeds the MRZ)
    #   expiry_preset   — one of EXPIRY_PRESETS.keys
    class PassportPdf
      EXPIRY_PRESETS = {
        "valid" => -> { Date.current + 2.years },
        "expires_60" => -> { Date.current + 60.days },
        "expires_30" => -> { Date.current + 30.days },
        "expired" => -> { Date.current - 1.day }
      }.freeze

      FONT_DIR = Rails.root.join("app/assets/fonts")

      def self.call(persona:, options:)
        new(persona: persona, options: options).call
      end

      def self.expiry_date_for(preset)
        (EXPIRY_PRESETS[preset.to_s] || EXPIRY_PRESETS["valid"]).call
      end

      def initialize(persona:, options:)
        @persona = persona
        @place_of_birth = options.fetch(:place_of_birth)
        @passport_number = options.fetch(:passport_number).to_s.upcase
        @expiry_date = self.class.expiry_date_for(options[:expiry_preset])
        @mrz = PassportMrz.call(persona: persona, document_number: @passport_number, expiry_date: @expiry_date)
      end

      def call
        Prawn::Document.new(page_size: [ 360, 260 ], margin: 20) do |pdf|
          pdf.font_families.update(
            "DejaVu" => {
              normal: FONT_DIR.join("DejaVuSans.ttf").to_s,
              bold: FONT_DIR.join("DejaVuSans-Bold.ttf").to_s
            }
          )
          pdf.font "DejaVu"
          render_watermark(pdf)
          render_header(pdf)
          render_photo_placeholder(pdf)
          render_fields(pdf)
          render_mrz(pdf)
        end.render
      end

      private

      def render_watermark(pdf)
        pdf.fill_color "DDDDDD"
        pdf.rotate(30, origin: [ pdf.bounds.width / 2, pdf.bounds.height / 2 ]) do
          pdf.text_box "SPECIMEN", at: [ 0, (pdf.bounds.height / 2) + 30 ],
                        width: pdf.bounds.width, align: :center, size: 44, style: :bold
        end
        pdf.fill_color "000000"
      end

      def render_header(pdf)
        pdf.fill_color "1B3A5C"
        pdf.text "REPUBLIC OF UTOPIA", size: 13, style: :bold
        pdf.fill_color "CC0000"
        pdf.text "PASSPORT — SPECIMEN — TEST DATA", size: 9, style: :bold
        pdf.fill_color "000000"
        pdf.move_down 8
      end

      def render_photo_placeholder(pdf)
        origin_y = pdf.cursor
        pdf.stroke_color "999999"
        pdf.fill_color "DDDDDD"
        pdf.fill_and_stroke_rectangle [ 0, origin_y ], 70, 90
        pdf.fill_color "000000"
        pdf.stroke_color "000000"
      end

      def render_fields(pdf)
        top = pdf.cursor
        pdf.bounding_box([ 85, top ], width: pdf.bounds.width - 85, height: 95) do
          field(pdf, "Surname", @persona.surname)
          field(pdf, "Given names", @persona.given_names)
          field(pdf, "Nationality", "UTOPIAN")
          field(pdf, "Date of birth", @persona.date_of_birth.strftime("%d %b %Y"))
          field(pdf, "Sex", sex_label)
          field(pdf, "Place of birth", @place_of_birth)
          field(pdf, "Passport No.", @passport_number)
          field(pdf, "Date of expiry", @expiry_date.strftime("%d %b %Y"))
        end
        pdf.move_cursor_to top - 95
      end

      def field(pdf, label, value)
        pdf.text "#{label}: #{value}", size: 8
      end

      def sex_label
        { "male" => "M", "female" => "F" }.fetch(@persona.sex, "X")
      end

      def render_mrz(pdf)
        pdf.move_down 10
        pdf.font "Courier", size: 10 do
          pdf.text @mrz.line1
          pdf.text @mrz.line2
        end
      end
    end
  end
end
