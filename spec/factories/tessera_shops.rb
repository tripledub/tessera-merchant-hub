# frozen_string_literal: true

# Factory for the MerchantHub-owned Shop model (ADR-007).
# The :tessera_shop alias is kept for backward compatibility with existing specs.
FactoryBot.define do
  factory :tessera_shop, class: "Shop" do
    sequence(:shop_id) { |n| "shop_#{n}" }
    integration_account_id { shop_id }
    merchant_id { "merch_#{SecureRandom.hex(3)}" }
    name { "Shop #{SecureRandom.hex(3)}" }
    notification_url { "https://example.com/webhooks" }
    test_mode { false }
    country { "GB" }
  end
end
