# frozen_string_literal: true

# MH-394: the applicant layout chooses its content column from a width a page
# declares with `content_for :applicant_width` ("narrow" is the default).
module ApplicantLayoutHelper
  CONTENT_WIDTHS = {
    "narrow" => "max-w-[720px]",
    "wide" => "max-w-[1120px]"
  }.freeze

  def applicant_content_width_class
    CONTENT_WIDTHS.fetch(content_for(:applicant_width).to_s, CONTENT_WIDTHS.fetch("narrow"))
  end
end
