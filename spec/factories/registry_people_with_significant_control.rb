# frozen_string_literal: true

FactoryBot.define do
  factory :registry_person_with_significant_control, class: "Registry::PersonWithSignificantControl" do
    association :registry_profile
    name { "Mr Albert Edward Short" }
    kind { "individual-person-with-significant-control" }
    natures_of_control { [ "ownership-of-shares-75-to-100-percent" ] }
    notified_on { Date.new(2020, 1, 1) }
    ceased_on { nil }
    nationality { "British" }
    date_of_birth_month { 7 }
    date_of_birth_year { 1975 }
    line1 { "10 Business Park" }
    city { "Bristol" }
    postcode { "BS1 1AA" }
    country { "United Kingdom" }
  end
end
