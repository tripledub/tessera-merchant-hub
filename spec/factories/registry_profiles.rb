# frozen_string_literal: true

FactoryBot.define do
  factory :registry_profile, class: "Registry::Profile" do
    association :applicant
    jurisdiction { "gb" }
    company_number { "12345678" }
    company_name { "Acme Ltd" }
    status { "active" }
    incorporated_on { Date.new(2020, 1, 1) }
    fetched_at { Time.current }
    raw_response { {} }
  end
end
