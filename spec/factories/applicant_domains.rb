# frozen_string_literal: true

FactoryBot.define do
  factory :applicant_domain do
    association :applicant
    sequence(:name) { |n| "example#{n}.com" }
  end
end
