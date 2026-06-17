# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_principal do
    association :applicant
    name { "#{Faker::Name.first_name} #{Faker::Name.last_name}" }
    role { :director }
  end
end
