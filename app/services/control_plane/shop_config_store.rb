# frozen_string_literal: true

module ControlPlane
  # MerchantHub-owned shop presentation config (notification URL, test mode).
  class ShopConfigStore
    def self.update!(shop_id:, notification_url: nil, test_mode: nil)
      new.update!(shop_id: shop_id, notification_url: notification_url, test_mode: test_mode)
    end

    def update!(shop_id:, notification_url: nil, test_mode: nil)
      conn = ActiveRecord::Base.connection
      sets = []
      sets << "notification_url = #{conn.quote(notification_url)}" unless notification_url.nil?
      sets << "test_mode = #{test_mode ? 'TRUE' : 'FALSE'}" unless test_mode.nil?
      sets << "updated_at = #{conn.quote(Time.current)}"

      return { "shop_id" => shop_id } if sets.empty?

      rows_affected = conn.update(<<~SQL.squish)
        UPDATE shops
        SET #{sets.join(', ')}
        WHERE shop_id = #{conn.quote(shop_id)}
      SQL

      raise ActiveRecord::RecordNotFound, "Shop not found: #{shop_id}" if rows_affected.zero?

      {
        "shop_id" => shop_id,
        "notification_url" => notification_url,
        "test_mode" => test_mode
      }.compact
    end
  end
end
