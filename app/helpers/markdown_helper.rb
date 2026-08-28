# frozen_string_literal: true

module MarkdownHelper
  # Used in views — returns html_safe so Rails won't double-escape it.
  def render_markdown(text)
    MarkdownRenderer.call(text).html_safe
  end

  module_function :render_markdown
end
