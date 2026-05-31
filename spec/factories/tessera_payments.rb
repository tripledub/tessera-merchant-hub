# frozen_string_literal: true

FactoryBot.define do
  factory :tessera_payment, class: "Tessera::Payment" do
    id { SecureRandom.uuid }
    shop_id { "shop_#{SecureRandom.hex(4)}" }
    status { "authorised" }
    amount { 1000 }
    currency { "GBP" }
    idempotency_key { SecureRandom.uuid }
    merchant_reference { "ref_#{SecureRandom.hex(4)}" }
    inserted_at { Time.current }
    updated_at { Time.current }

    # Bypass readonly? guard — test data only; production tables are owned by tessera-core
    to_create do |instance|
      attrs = instance.attributes.compact
      cols = attrs.keys.map { |k| %("#{k}") }.join(", ")
      vals = attrs.values.map { |v| ActiveRecord::Base.connection.quote(v) }.join(", ")
      ActiveRecord::Base.connection.execute(
        "INSERT INTO payments (#{cols}) VALUES (#{vals})"
      )
      instance.instance_variable_set(:@new_record, false)
      instance
    end
  end
end
