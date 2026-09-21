# frozen_string_literal: true

FactoryBot.define do
  factory :domain_blocklist_entry do
    sequence(:name) { |n| "registrar#{n}.com" }
  end
end
