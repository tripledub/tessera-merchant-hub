# frozen_string_literal: true

FactoryBot.define do
  factory :shop do
    sequence(:shop_id) { |n| "shop_#{n}" }
    integration_account_id { shop_id }
    merchant_id { "merch_#{SecureRandom.hex(3)}" }
    name { "Shop #{SecureRandom.hex(3)}" }
    notification_url { "https://example.com/webhooks" }
    test_mode { false }
    country { "GB" }

    trait :with_merchant do
      transient do
        merchant { nil }
      end

      after(:build) do |shop, evaluator|
        merchant = evaluator.merchant || build(:merchant, merchant_id: shop.merchant_id)
        merchant.save! unless merchant.persisted?
        shop.merchant_id = merchant.merchant_id
      end
    end
  end
end
