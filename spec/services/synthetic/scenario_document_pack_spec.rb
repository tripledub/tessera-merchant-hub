# frozen_string_literal: true

require "rails_helper"

RSpec.describe Synthetic::ScenarioDocumentPack do
  let(:persona) { create(:synthetic_persona, given_names: "Pack", surname: "Test") }

  let(:scenario) do
    Synthetic::ScenarioCatalogue::Scenario.new(
      id: "pack-test", title: "Pack test", company_number: "XU000001",
      people: [
        Synthetic::ScenarioCatalogue::Person.new(
          persona_slug: persona.slug, role: "director",
          documents: [
            Synthetic::ScenarioCatalogue::Document.new(
              type: "passport",
              options: { place_of_birth: "Testville", passport_number: "L898902C3", expiry_preset: "valid" }
            )
          ]
        )
      ],
      ground_truth: "...", qase_cases: [ "KYN-1" ]
    )
  end

  it "builds a zip containing one entry per generated document" do
    data = described_class.call(scenario)

    entries = []
    Zip::InputStream.open(StringIO.new(data)) do |io|
      while (entry = io.get_next_entry)
        entries << entry.name
      end
    end

    expect(entries).to eq([ "#{persona.slug}-passport.pdf" ])
  end

  it "each entry is valid PDF data" do
    data = described_class.call(scenario)

    Zip::InputStream.open(StringIO.new(data)) do |io|
      io.get_next_entry
      expect(io.read).to start_with("%PDF")
    end
  end
end
