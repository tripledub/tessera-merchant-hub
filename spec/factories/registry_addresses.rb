# frozen_string_literal: true

FactoryBot.define do
  factory :registry_address, class: "Registry::Address" do
    association :registry_profile
    kind { "registered" }
    line1 { "10 Business Park" }
    city { "Bristol" }
    postcode { "BS1 1AA" }
    country { "United Kingdom" }
  end
end
