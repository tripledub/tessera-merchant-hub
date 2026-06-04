# frozen_string_literal: true

module ControlPlane
  # Creates a MerchantHub shop row and the backing core integration account.
  class ShopProvisioner
    def self.create!(merchant_id:, name:, country:, notification_url: nil, shop_id: nil, client: TesseraCoreClient.new)
      new(client: client).create!(
        merchant_id: merchant_id,
        name: name,
        country: country,
        notification_url: notification_url,
        shop_id: shop_id
      )
    end

    def initialize(client: TesseraCoreClient.new)
      @client = client
    end

    def create!(merchant_id:, name:, country:, notification_url: nil, shop_id: nil)
      shop_id ||= "shop_#{SecureRandom.urlsafe_base64(9)}"
      secret_key = "sk_#{SecureRandom.urlsafe_base64(18)}"

      account = @client.create_integration_account(
        merchant_hub_merchant_id: merchant_id,
        merchant_hub_shop_id: shop_id,
        secret_key: secret_key
      )

      integration_account_id = account.fetch("id")
      row_id = SecureRandom.uuid
      now = Time.current
      conn = ActiveRecord::Base.connection

      conn.insert(
        "INSERT INTO shops (id, shop_id, merchant_id, integration_account_id, name, notification_url, " \
        "test_mode, country, inserted_at, updated_at) " \
        "VALUES (#{conn.quote(row_id)}, #{conn.quote(shop_id)}, #{conn.quote(merchant_id)}, " \
        "#{conn.quote(integration_account_id)}, #{conn.quote(name)}, #{conn.quote(notification_url)}, " \
        "FALSE, #{conn.quote(country)}, #{conn.quote(now)}, #{conn.quote(now)})"
      )

      {
        "shop_id" => shop_id,
        "integration_account_id" => integration_account_id,
        "name" => name,
        "country" => country,
        "notification_url" => notification_url
      }
    end
  end
end
