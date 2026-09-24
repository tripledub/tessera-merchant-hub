# frozen_string_literal: true

require "rails_helper"

# MH-309 AC3: a persona survives the UAT DB reset by being exported to YAML
# and reseeded. This spec simulates that reset directly (export, destroy the
# DB row, seed) rather than actually resetting the database.
RSpec.describe Synthetic::PersonaSeed do
  let(:persona) do
    create(:synthetic_persona, given_names: "Reset Test", surname: "Persona",
      date_of_birth: Date.new(1995, 7, 1), sex: :female, jurisdiction: "xu")
  end

  after { FileUtils.rm_f(Synthetic::PersonaExport::DIR.join("#{persona.slug}.yml")) }

  it "reappears after being exported, deleted, and reseeded" do
    Synthetic::PersonaExport.call(persona)
    slug = persona.slug
    persona.destroy!

    expect(Synthetic::Persona.find_by(slug: slug)).to be_nil

    described_class.call

    reseeded = Synthetic::Persona.find_by!(slug: slug)
    expect(reseeded.given_names).to eq("Reset Test")
    expect(reseeded.surname).to eq("Persona")
    expect(reseeded.date_of_birth).to eq(Date.new(1995, 7, 1))
    expect(reseeded.sex).to eq("female")
    expect(reseeded.jurisdiction).to eq("xu")
  end

  it "is idempotent — updates the existing row rather than duplicating it" do
    Synthetic::PersonaExport.call(persona)

    expect { described_class.call }.not_to change(Synthetic::Persona, :count)
  end
end
