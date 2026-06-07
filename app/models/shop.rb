# frozen_string_literal: true

# MerchantHub-owned shop / storefront. Links to tessera-core via integration_account_id.
class Shop < ApplicationRecord
  belongs_to :merchant,
    foreign_key: :merchant_id,
    primary_key: :merchant_id,
    inverse_of: :shops,
    optional: true

  scope :for_merchant, ->(merchant_id) { where(merchant_id: merchant_id) }

  validates :shop_id, presence: true, uniqueness: true
  validates :merchant_id, presence: true
  validates :integration_account_id, presence: true
  validates :name, presence: true

  def to_param
    shop_id
  end
end
