# frozen_string_literal: true

FactoryBot.define do
  factory :address do
    line1    { "1 Test Street" }
    city     { "London" }
    postcode { "EC1A 1BB" }
    country  { "United Kingdom" }
    primary  { false }
    association :addressable, factory: :applicant

    trait :business do
      type { "Address::Business" }
    end

    trait :individual do
      type { "Address::Individual" }
    end

    trait :primary do
      primary { true }
    end
  end
end
