# frozen_string_literal: true

FactoryBot.define do
  factory :applicant do
    name { "Applicant #{SecureRandom.hex(3)}" }
    company_name { "Co #{SecureRandom.hex(3)} Ltd" }
    contact_email { "#{SecureRandom.hex(4)}@example.com" }
    country { "GB" }
    country_code { "GB" }
    status { :pending }
  end
end
