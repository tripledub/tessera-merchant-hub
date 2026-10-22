# frozen_string_literal: true

require "rails_helper"

# MH-402: the placeholder logo is attached inline to every email and drawn at 36-48px,
# so it must stay small. (The real logo replaces it before launch: MH-423.)
RSpec.describe "Brand assets", type: :feature do
  let(:logo) { Rails.root.join("app/assets/images/kynetic-icon.png") }

  it "keeps the placeholder logo under 30 KB" do
    expect(logo.size).to be < 30.kilobytes
  end

  it "keeps it large enough to be sharp at 48px on a high-density screen" do
    width, height = logo.binread(24)[16, 8].unpack("NN")

    expect([ width, height ]).to eq([ 192, 192 ])
  end

  it "ships the flags the country chips use, with the flag-icons licence beside them" do
    %w[gb mt cy globe].each { |name| expect(Rails.root.join("app/assets/images/flags/#{name}.svg")).to exist }
    expect(Rails.root.join("app/assets/images/flags/FLAG-ICONS-LICENSE.txt").read).to include("MIT License")
  end
end
