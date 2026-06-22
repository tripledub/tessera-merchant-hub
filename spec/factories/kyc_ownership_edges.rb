# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_ownership_edge, class: "Kyc::OwnershipEdge" do
    association :parent_entity, factory: :kyc_corporate_entity
    association :child_entity, factory: :kyc_corporate_entity
    relationship_type { :equity }
    percentage { 100.0 }
  end
end
