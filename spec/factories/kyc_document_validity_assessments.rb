# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_document_validity_assessment, class: "Kyc::DocumentValidityAssessment" do
    association :kyc_document
    association :kyc_document_validity_policy
    policy_version { kyc_document_validity_policy.version }
    assessed_at { Time.current }
    reference_date { Date.current }
    dates_used { { "expiry" => { "date" => "2030-01-01", "source" => "extracted" } } }
    outcome { :valid }
    reason_code { "within_validity_window" }
    reason_details { nil }
  end
end
