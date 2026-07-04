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

  def render_markdown(text)
    return "" if text.blank?

    raw_html = RENDERER.render(text)
    sanitized = SANITIZER.sanitize(raw_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRS)
    sanitized.html_safe
  end

  module_function :render_markdown
end
