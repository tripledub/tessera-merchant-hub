# frozen_string_literal: true

require "rails_helper"

# MH-398: the applicant chat uses shared bubble, typing and progress utilities
# so the server-rendered markup and the JS-built bubbles cannot drift apart.
# Same contract as the other applicant primitives: kyn-* tokens only, no dark
# variants. `.chat-prose` is shared with the admin transcript view and must not
# change.
RSpec.describe "Applicant chat utilities" do # rubocop:disable RSpec/DescribeClass
  let(:css) { Rails.root.join("app/assets/tailwind/application.css").read }
  let(:chat_utilities) do
    %w[kyn-bubble kyn-bubble-assistant kyn-bubble-applicant kyn-typing-dot kyn-progress kyn-progress-fill kyn-chip]
  end

  def utility_block(name)
    start = css.index(/^@utility #{Regexp.escape(name)} \{/)
    return nil unless start

    depth = 0
    opened = false
    css[start..].each_char.with_index do |char, index|
      if char == "{"
        depth += 1
        opened = true
      elsif char == "}"
        depth -= 1
      end
      return css[start..(start + index)] if opened && depth.zero?
    end
    nil
  end

  it "defines every chat utility" do
    expect(chat_utilities.reject { |name| utility_block(name) }).to be_empty
  end

  it "styles them from kyn tokens only, with no admin colour scales" do
    admin_scale = /(?<![a-z-])(gray|brand|success|error|warning|orange|blue-light)-\d{2,3}/

    offenders = chat_utilities.select { |name| utility_block(name).match?(admin_scale) }

    expect(offenders).to be_empty
  end

  it "adds no dark variants" do
    expect(chat_utilities.select { |name| utility_block(name).include?("dark:") }).to be_empty
  end

  it "gives the assistant bubble the grey token and a small bottom-left corner" do
    block = utility_block("kyn-bubble-assistant")

    expect(block).to include("bg-kyn-assistant-bubble")
    expect(block).to include("rounded-bl-")
  end

  it "gives the applicant bubble the primary token, white text and a small bottom-right corner" do
    block = utility_block("kyn-bubble-applicant")

    expect(block).to include("bg-kyn-primary")
    expect(block).to include("text-kyn-surface")
    expect(block).to include("rounded-br-")
  end

  it "wraps long words inside bubbles" do
    expect(utility_block("kyn-bubble")).to include("overflow-wrap:anywhere")
  end

  it "fills the progress bar with the brand gradient" do
    expect(utility_block("kyn-progress-fill")).to include("var(--kyn-gradient-brand)")
    expect(css).to include('--kyn-gradient-brand: linear-gradient(90deg, #00d5fd, #2e88fb, #7e32f9)')
  end

  it "turns the typing animation off for reduced motion" do
    block = utility_block("kyn-typing-dot")

    expect(block).to include("animation")
    expect(block).to match(/prefers-reduced-motion: reduce\)\s*\{[^}]*animation: none/)
  end

  it "makes chips at least 44px tall, fully rounded, with a hover tint and a focus ring (MH-399)" do
    block = utility_block("kyn-chip")

    expect(block).to include("min-h-[44px]")
    expect(block).to include("rounded-full")
    expect(block).to include("bg-kyn-primary-tint")
    expect(block).to include("focus-visible")
    expect(block).to include("ring-kyn-primary")
  end

  it "leaves the shared .chat-prose rules (used by the admin transcript view) untouched" do
    expect(css).to include(".chat-prose a { @apply text-brand-500 underline hover:text-brand-600; }")
    expect(css).to include(".chat-prose code { @apply rounded bg-gray-200 px-1 py-0.5 text-xs dark:bg-gray-700;")
  end

  it "recolours markdown inside the applicant assistant bubble with unlayered kyn-only rules" do
    rules = css.scan(/^\.chat-prose\.kyn-bubble-assistant[^{]*\{[^}]*\}/m)

    expect(rules).not_to be_empty
    expect(rules.join).to include("kyn-primary-text")
    expect(rules.join).not_to match(/(?<![a-z-])(gray|brand)-\d{2,3}|dark:/)
  end
end
