# frozen_string_literal: true

# MerchantHub-owned merchant (company) record. ADR-007.
class Merchant < ApplicationRecord
  has_many :shops,
    foreign_key: :merchant_id,
    primary_key: :merchant_id,
    inverse_of: :merchant,
    dependent: :restrict_with_error

  validates :merchant_id, presence: true, uniqueness: true
  validates :name, presence: true
end
