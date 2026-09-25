# frozen_string_literal: true

module Synthetic
  # MH-309: reseeds Synthetic::Persona records from every YAML file under
  # config/synthetic/personas/ (see Synthetic::PersonaExport), so a persona
  # crafted once and exported reappears after the UAT DB reset (MH-315). Run
  # via `rails kyc:synthetic:seed`. Idempotent — matches on slug, so running
  # it again after edits to a YAML file updates the existing row in place.
  class PersonaSeed
    DIR = PersonaExport::DIR

    def self.call
      new.call
    end

    def call
      files.each { |file| seed_file(file) }
      files.size
    end

    private

    def files
      Dir.glob(DIR.join("*.yml")).sort
    end

    def seed_file(file)
      data = YAML.safe_load_file(file)
      persona = Persona.find_or_initialize_by(slug: data.fetch("slug"))
      persona.assign_attributes(
        given_names: data.fetch("given_names"),
        surname: data.fetch("surname"),
        date_of_birth: Date.iso8601(data.fetch("date_of_birth")),
        sex: data.fetch("sex"),
        jurisdiction: data.fetch("jurisdiction")
      )
      persona.save!
    end
  end
end
