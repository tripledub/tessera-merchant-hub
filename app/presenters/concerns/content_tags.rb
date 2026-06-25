# frozen_string_literal: true

module ContentTags
  BADGE_COLOURS = {
    green:  "bg-green-50 text-green-700 dark:bg-green-500/10 dark:text-green-400",
    red:    "bg-red-50 text-red-700 dark:bg-red-500/10 dark:text-red-400",
    amber:  "bg-amber-50 text-amber-700 dark:bg-amber-500/10 dark:text-amber-400",
    blue:   "bg-blue-50 text-blue-700 dark:bg-blue-500/10 dark:text-blue-400",
    gray:   "bg-gray-100 text-gray-700 dark:bg-gray-500/10 dark:text-gray-400"
  }.freeze

  DOT_COLOURS = {
    green: "bg-green-500",
    red:   "bg-red-500",
    amber: "bg-amber-500",
    blue:  "bg-blue-500",
    gray:  "bg-gray-400"
  }.freeze

  def badge(text, colour = :gray)
    classes = BADGE_COLOURS.fetch(colour, BADGE_COLOURS[:gray])
    content_tag(:span, text, class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{classes}")
  end

  def definition_row(label, value)
    content_tag(:dt, label, class: "text-theme-sm font-medium text-gray-500 dark:text-gray-400") +
      content_tag(:dd, value, class: "text-theme-sm text-gray-800 dark:text-white/90")
  end

  def source_badge(record)
    if record.applicant_declared?
      badge(I18n.t("kyc.source.applicant_declared"), :amber)
    else
      badge(I18n.t("kyc.source.document_extracted"), :blue)
    end
  end

  def status_dot(label, colour = :gray)
    dot = content_tag(:span, "", class: "inline-block h-2 w-2 rounded-full #{DOT_COLOURS.fetch(colour, DOT_COLOURS[:gray])}")
    content_tag(:span, class: "inline-flex items-center gap-1.5 text-theme-sm") do
      dot + label
    end
  end
end
