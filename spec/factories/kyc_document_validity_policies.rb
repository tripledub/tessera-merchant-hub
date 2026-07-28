# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_document_validity_policy, class: "Kyc::DocumentValidityPolicy" do
    document_type { "passport" }
    sequence(:version)
    effective_from { Date.current }
    mode { :expires }
    required_dates { [ "expiry" ] }
    warning_thresholds { [ 90, 30 ] }
    max_age_months { nil }
    blocking { true }
    enabled { true }

    trait :freshness do
      document_type { "utility_bill" }
      mode { :freshness }
      required_dates { [ "issued" ] }
      warning_thresholds { [] }
      max_age_months { 3 }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
