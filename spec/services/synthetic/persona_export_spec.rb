# frozen_string_literal: true

require "rails_helper"

RSpec.describe Synthetic::PersonaExport do
  let(:persona) do
    create(:synthetic_persona, given_names: "Export Test", surname: "Persona",
      date_of_birth: Date.new(1985, 3, 4), sex: :male, jurisdiction: "xu")
  end

  after { FileUtils.rm_f(described_class::DIR.join("#{persona.slug}.yml")) }

  it "writes a YAML file named after the persona's slug" do
    path = described_class.call(persona)

    expect(path).to eq(described_class::DIR.join("#{persona.slug}.yml"))
    expect(File).to exist(path)
  end

  it "round-trips every persisted field" do
    path = described_class.call(persona)
    data = YAML.safe_load_file(path)

    expect(data).to eq(
      "slug" => persona.slug,
      "given_names" => "Export Test",
      "surname" => "Persona",
      "date_of_birth" => "1985-03-04",
      "sex" => "male",
      "jurisdiction" => "xu"
    )
  end
end
