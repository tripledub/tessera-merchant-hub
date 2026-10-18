# frozen_string_literal: true

require "rails_helper"

# MH-394: the applicant theme lives in the shared Tailwind source next to the
# admin theme. These specs pin the kyn-* tokens to the Figma file (Kynetic
# Applicant and Kynetic Shape variable collections) so a drifting value or an
# invented token fails loudly, and they pin the font setup that keeps applicant
# pages from calling Google Fonts.
RSpec.describe "Applicant theme tokens" do # rubocop:disable RSpec/DescribeClass
  let(:css) { Rails.root.join("app/assets/tailwind/application.css").read }

  let(:figma_colors) do
    {
      "primary" => "#4f5bf5",
      "primary-hover" => "#4650e0",
      "primary-disabled" => "#a7adfa",
      "primary-tint" => "#eef0fe",
      "primary-text" => "#3f4bd8",
      "navy" => "#0e1b2b",
      "slate" => "#5b6878",
      "bg" => "#f7f9fc",
      "surface" => "#ffffff",
      "assistant-bubble" => "#f0f3f7",
      "border" => "#e2e8f0",
      "error" => "#c9342b",
      "error-tint" => "#fdf3f2",
      "success" => "#0b7a4b",
      "success-tint" => "#e7f4ee",
      "warning" => "#8a5a00",
      "warning-tint" => "#fdf3e1"
    }
  end

  let(:figma_radii) { { "md" => "12px", "lg" => "16px", "full" => "9999px" } }

  it "defines exactly the Figma colour tokens with Figma values" do
    colors = css.scan(/--color-kyn-([a-z-]+):\s*(#[0-9a-fA-F]{6})\s*;/).to_h { |name, hex| [ name, hex.downcase ] }

    expect(colors).to eq(figma_colors)
  end

  it "defines exactly the Figma radius tokens with Figma values" do
    radii = css.scan(/--radius-kyn-([a-z-]+):\s*([0-9a-z.]+)\s*;/).to_h

    expect(radii).to eq(figma_radii)
  end

  it "exposes a font-kynetic family with a system fallback stack" do
    family = css[/--font-kynetic:\s*([^;]+);/, 1]

    expect(family).to start_with("\"Plus Jakarta Sans\"")
    expect(family).to include("system-ui")
  end

  it "self-hosts Plus Jakarta Sans for the weights the design uses" do
    faces = css.scan(/@font-face\s*\{[^}]*\}/m).select { |face| face.include?("Plus Jakarta Sans") }
    weights = faces.flat_map { |face| face[/font-weight:\s*([^;]+);/, 1].to_s.scan(/\d+/).map(&:to_i) }

    expect(faces).not_to be_empty
    expect(faces.join).to include('url(')
    expect(faces.join).not_to include("http")
    expect(weights.minmax).to eq([ 400, 700 ])
  end

  it "no longer imports Google Fonts from the shared stylesheet" do
    expect(css).not_to include("fonts.googleapis.com")
    expect(css).not_to include("fonts.gstatic.com")
  end

  it "adds no dark variants to the kyn tokens" do
    expect(css.scan(/dark:[^\s;]*kyn-/)).to be_empty
  end
end
