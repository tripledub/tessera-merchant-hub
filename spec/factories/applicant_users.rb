# frozen_string_literal: true

FactoryBot.define do
  factory :applicant_user do
    association :applicant
    sequence(:email) { |n| "applicant#{n}@example.com" }
    password { "password123!" }
    first_name { "Test" }
    last_name { "Applicant" }
    confirmed_at { Time.current }

    trait :unconfirmed do
      confirmed_at { nil }
    end

    # What a one-time-code sign-in creates: an email and nothing else.
    trait :nameless do
      first_name { nil }
      last_name { nil }
      password { nil }
    end
  end
end
