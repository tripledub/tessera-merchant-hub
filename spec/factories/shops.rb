FactoryBot.define do
  factory :shop do
    sequence(:shop_id) { |n| "shop_#{n}" }
    sequence(:name)    { |n| "Store #{n}" }
    notification_url { "https://example.com/webhooks" }
    test_mode { false }
  end
end
