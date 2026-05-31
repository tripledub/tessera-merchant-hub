FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123!" }
    role { :psp_admin }
    shop_id { nil }

    trait :psp_admin do
      role { :psp_admin }
      shop_id { nil }
    end

    trait :psp_support do
      role { :psp_support }
      shop_id { nil }
    end

    trait :merchant_admin do
      role { :merchant_admin }
      sequence(:shop_id) { |n| n }
    end

    trait :merchant_viewer do
      role { :merchant_viewer }
      sequence(:shop_id) { |n| n }
    end
  end
end
