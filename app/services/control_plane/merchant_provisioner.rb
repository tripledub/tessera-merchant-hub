# frozen_string_literal: true

module ControlPlane
  # Creates a MerchantHub-owned Merchant record (ADR-007).
  class MerchantProvisioner
    def self.create!(name:, company_name: nil, country: nil)
      new.create!(name: name, company_name: company_name, country: country)
    end

    def create!(name:, company_name: nil, country: nil)
      merchant_id = "merch_#{SecureRandom.urlsafe_base64(9)}"

      Merchant.create!(
        merchant_id: merchant_id,
        name: name,
        company_name: company_name,
        country: country
      )

      {
        "merchant_id" => merchant_id,
        "name" => name,
        "company_name" => company_name,
        "country" => country
      }
    end
  end
end
