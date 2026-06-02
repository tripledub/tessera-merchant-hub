FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123!" }
    role { :psp_admin }
    merchant_id { nil }

    trait :psp_admin do
      role { :psp_admin }
      merchant_id { nil }
    end

    trait :psp_support do
      role { :psp_support }
      merchant_id { nil }
    end

    trait :merchant_admin do
      role { :merchant_admin }
      sequence(:merchant_id) { |n| "merch_#{n}" }
    end

    trait :merchant_viewer do
      role { :merchant_viewer }
      sequence(:merchant_id) { |n| "merch_#{n}" }
    end
  end
end
