# frozen_string_literal: true

FactoryBot.define do
  factory :tessera_shop, class: "Tessera::Shop" do
    id { SecureRandom.uuid }
    sequence(:shop_id) { |n| "shop_#{n}" }
    integration_account_id { shop_id }
    merchant_id { "merch_#{SecureRandom.hex(3)}" }
    name { "Shop #{SecureRandom.hex(3)}" }
    notification_url { "https://example.com/webhooks" }
    test_mode { false }
    country { "GB" }
    inserted_at { Time.current }
    updated_at { Time.current }

    # Bypass readonly? guard — test data only; tessera-core owns this table.
    to_create do |instance|
      attrs = instance.attributes.compact
      cols = attrs.keys.map { |k| %("#{k}") }.join(", ")
      vals = attrs.values.map { |v| ActiveRecord::Base.connection.quote(v) }.join(", ")
      ActiveRecord::Base.connection.execute("INSERT INTO shops (#{cols}) VALUES (#{vals})")
      instance.instance_variable_set(:@new_record, false)
      instance
    end
  end
end
