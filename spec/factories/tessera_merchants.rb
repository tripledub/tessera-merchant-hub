# frozen_string_literal: true

# Factory for the MerchantHub-owned Merchant model (ADR-007).
# The :tessera_merchant alias is kept for backward compatibility with existing specs.
FactoryBot.define do
  factory :tessera_merchant, class: "Merchant" do
    sequence(:merchant_id) { |n| "merch_#{n}" }
    name { "Merchant #{SecureRandom.hex(3)}" }
    company_name { "Co #{SecureRandom.hex(3)} Ltd" }
    country { "GB" }
  end
end
