# frozen_string_literal: true

FactoryBot.define do
  factory :tessera_merchant, class: "Tessera::Merchant" do
    id { SecureRandom.uuid }
    sequence(:merchant_id) { |n| "merch_#{n}" }
    name { "Merchant #{SecureRandom.hex(3)}" }
    company_name { "Co #{SecureRandom.hex(3)} Ltd" }
    country { "GB" }
    inserted_at { Time.current }
    updated_at { Time.current }

    # Bypass readonly? guard — test data only; tessera-core owns this table.
    to_create do |instance|
      attrs = instance.attributes.compact
      cols = attrs.keys.map { |k| %("#{k}") }.join(", ")
      vals = attrs.values.map { |v| ActiveRecord::Base.connection.quote(v) }.join(", ")
      ActiveRecord::Base.connection.execute("INSERT INTO merchants (#{cols}) VALUES (#{vals})")
      instance.instance_variable_set(:@new_record, false)
      instance
    end
  end
end
