# frozen_string_literal: true

module ControlPlane
  # MerchantHub-owned shop presentation config (notification URL, test mode).
  class ShopConfigStore
    def self.update!(shop_id:, notification_url: nil, test_mode: nil)
      new.update!(shop_id: shop_id, notification_url: notification_url, test_mode: test_mode)
    end

    def update!(shop_id:, notification_url: nil, test_mode: nil)
      attrs = {}
      attrs[:notification_url] = notification_url unless notification_url.nil?
      attrs[:test_mode] = test_mode unless test_mode.nil?

      return { "shop_id" => shop_id } if attrs.empty?

      rows_affected = Shop.where(shop_id: shop_id).update_all(attrs.merge(updated_at: Time.current))

      raise ActiveRecord::RecordNotFound, "Shop not found: #{shop_id}" if rows_affected.zero?

      {
        "shop_id" => shop_id,
        "notification_url" => notification_url,
        "test_mode" => test_mode
      }.compact
    end
  end
end
