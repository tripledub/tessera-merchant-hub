# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_document_replacement_requirement, class: "Kyc::DocumentReplacementRequirement" do
    association :kyc_document
    status { :warned }
    opened_at { Time.current }
  end
end
