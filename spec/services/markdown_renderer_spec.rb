# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarkdownRenderer do
  describe ".call" do
    it "returns an empty string for blank input" do
      expect(described_class.call(nil)).to eq("")
      expect(described_class.call("")).to eq("")
    end

    it "renders markdown to sanitized HTML" do
      html = described_class.call("**bold** and _italic_")

      expect(html).to include("<strong>bold</strong>")
      expect(html).to include("<em>italic</em>")
    end

    it "strips tags outside the allow-list" do
      html = described_class.call("<script>alert('xss')</script>text")

      expect(html).not_to include("<script>")
      expect(html).to include("text")
    end

    it "adds target and rel attributes to links" do
      html = described_class.call("[link](https://example.com)")

      expect(html).to include('target="_blank"')
      expect(html).to include('rel="noopener noreferrer"')
    end
  end
end
