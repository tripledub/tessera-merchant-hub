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
  validates :contact_email,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    allow_blank: true
  validates :country_code,
    format: { with: /\A[A-Z]{2}\z/ },
    allow_blank: true

  before_validation :upcase_country_code

  def to_param
    merchant_id
  end

  private

  def upcase_country_code
    self.country_code = country_code&.upcase
  end
end
