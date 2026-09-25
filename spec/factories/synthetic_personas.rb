# frozen_string_literal: true

FactoryBot.define do
  factory :synthetic_persona, class: "Synthetic::Persona" do
    # Faker, not a fixed name — a fixed default previously collided with the
    # real committed config/synthetic/personas/alex-testperson.yml fixture
    # (MH-311's scenario catalogue), so a spec cleaning up its own exported
    # file by slug was deleting that real one too.
    given_names { Faker::Name.first_name }
    surname { Faker::Name.last_name }
    date_of_birth { Date.new(1990, 1, 1) }
    sex { :unspecified }
    jurisdiction { "xu" }
  end
end
