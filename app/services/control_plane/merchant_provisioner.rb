# frozen_string_literal: true

module ControlPlane
  # MerchantHub-owned merchant records (ADR-007). Not provisioned via tessera-core.
  class MerchantProvisioner
    def self.create!(name:, company_name: nil, country: nil)
      new.create!(name: name, company_name: company_name, country: country)
    end

    def create!(name:, company_name: nil, country: nil)
      merchant_id = "merch_#{SecureRandom.urlsafe_base64(9)}"
      row_id = SecureRandom.uuid
      now = Time.current
      conn = ActiveRecord::Base.connection

      conn.insert(
        "INSERT INTO merchants (id, merchant_id, name, company_name, country, inserted_at, updated_at) " \
        "VALUES (#{conn.quote(row_id)}, #{conn.quote(merchant_id)}, #{conn.quote(name)}, " \
        "#{conn.quote(company_name)}, #{conn.quote(country)}, #{conn.quote(now)}, #{conn.quote(now)})"
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
