# frozen_string_literal: true

FactoryBot.define do
  factory :merchant do
    sequence(:merchant_id) { |n| "merch_#{n}" }
    name { "Merchant #{SecureRandom.hex(3)}" }
    company_name { "Co #{SecureRandom.hex(3)} Ltd" }
    country { "GB" }
  end
end
