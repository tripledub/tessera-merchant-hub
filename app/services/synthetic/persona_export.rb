# frozen_string_literal: true

module Synthetic
  # MH-309: exports a persisted Synthetic::Persona to a git-committed YAML
  # file under config/synthetic/personas/, so it survives the UAT DB reset
  # (MH-315) — see Synthetic::PersonaSeed for the reverse, reseeding path.
  class PersonaExport
    DIR = Rails.root.join("config/synthetic/personas")

    def self.call(persona)
      new(persona).call
    end

    def initialize(persona)
      @persona = persona
    end

    def call
      FileUtils.mkdir_p(DIR)
      File.write(path, YAML.dump(attributes))
      path
    end

    private

    def path
      DIR.join("#{@persona.slug}.yml")
    end

    def attributes
      {
        "slug" => @persona.slug,
        "given_names" => @persona.given_names,
        "surname" => @persona.surname,
        "date_of_birth" => @persona.date_of_birth.iso8601,
        "sex" => @persona.sex,
        "jurisdiction" => @persona.jurisdiction
      }
    end
  end
end
