# frozen_string_literal: true

FactoryBot.define do
  factory :synthetic_persona, class: "Synthetic::Persona" do
    given_names { "Alex" }
    surname { "Testperson" }
    date_of_birth { Date.new(1990, 1, 1) }
    sex { :unspecified }
    jurisdiction { "xu" }
  end
end
