# frozen_string_literal: true

FactoryBot.define do
  factory :onboarding_application do
    applicant
    current_step { "company" }
    status { :draft }
  end
end
