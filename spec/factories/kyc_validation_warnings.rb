# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_validation_warning, class: "Kyc::ValidationWarning" do
    association :applicant
    association :kyc_document
    association :corporate_entity, factory: :kyc_corporate_entity
    warning_type { :percentage_deviation }
    message { "Ownership sums to 98.16% (expected 100%)" }
    metadata { { expected: 100.0, actual: 98.16, deviation: 1.84 } }
  end
end
