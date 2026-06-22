# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_corporate_entity, class: "Kyc::CorporateEntity" do
    association :applicant
    association :kyc_document
    name { "Acme Holdings Ltd" }
    entity_type { :corporate }
    jurisdiction { "GB" }
  end
end
