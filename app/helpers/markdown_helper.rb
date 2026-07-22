# frozen_string_literal: true

module MarkdownHelper
  RENDERER = Redcarpet::Markdown.new(
    Redcarpet::Render::HTML.new(hard_wrap: true, link_attributes: { target: "_blank", rel: "noopener noreferrer" }),
    autolink: true,
    tables: true,
    fenced_code_blocks: true,
    strikethrough: true,
    no_intra_emphasis: true
  )

  SANITIZER = Rails::Html::SafeListSanitizer.new

  ALLOWED_TAGS = %w[p br strong em ul ol li code pre a blockquote h1 h2 h3 h4 h5 h6 table thead tbody tr th td del].freeze
  ALLOWED_ATTRS = %w[href target rel].freeze

  # Used in views — returns html_safe so Rails won't double-escape it.
  def render_markdown(text)
    MarkdownHelper.render_to_html(text).html_safe
  end

  # Used outside views (e.g. ActionCable broadcasts) — returns a plain String
  # so JSON serialisation escapes < and > correctly via < / >.
  def self.render_to_html(text)
    return "" if text.blank?

    raw_html = RENDERER.render(text.to_s)
    SANITIZER.sanitize(raw_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRS).to_s
  end

  module_function :render_markdown
end
