# frozen_string_literal: true

FactoryBot.define do
  factory :tessera_webhook_delivery, class: "Tessera::WebhookDelivery" do
    id { SecureRandom.uuid }
    association :payment, factory: :tessera_payment
    status { "pending" }
    attempts { 0 }
    last_attempted_at { nil }
    delivered_at { nil }

    # Bypass readonly? guard — test data only; production tables are owned by tessera-core
    to_create do |instance|
      attrs = instance.attributes.except("payment").compact
      cols = attrs.keys.map { |k| %("#{k}") }.join(", ")
      vals = attrs.values.map { |v| ActiveRecord::Base.connection.quote(v) }.join(", ")
      ActiveRecord::Base.connection.execute(
        "INSERT INTO webhook_deliveries (#{cols}) VALUES (#{vals})"
      )
      instance.instance_variable_set(:@new_record, false)
      instance
    end
  end
end
