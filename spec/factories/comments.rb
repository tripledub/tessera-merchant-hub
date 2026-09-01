# frozen_string_literal: true

FactoryBot.define do
  factory :comment do
    association :commentable, factory: :kyc_document
    association :author, factory: :user
    body { "Looks good, proceeding." }
  end
end
