# frozen_string_literal: true

FactoryBot.define do
  factory :onboarding_message do
    onboarding_session
    role { :bot }
    content { "Hello, let's get started." }
    stage { "company_info" }
    structured_data { {} }
  end
end
