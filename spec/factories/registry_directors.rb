# frozen_string_literal: true

FactoryBot.define do
  factory :registry_director, class: "Registry::Director" do
    association :registry_profile
    name { "Jane Doe" }
    role { "director" }
    appointed_on { Date.new(2020, 1, 1) }
    resigned_on { nil }
  end
end
