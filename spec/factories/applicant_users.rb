# frozen_string_literal: true

FactoryBot.define do
  factory :applicant_user do
    association :applicant
    sequence(:email) { |n| "applicant#{n}@example.com" }
    password { "password123!" }
    first_name { "Test" }
    last_name { "Applicant" }
  end
end
