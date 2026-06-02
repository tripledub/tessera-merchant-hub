# frozen_string_literal: true

# This support file creates stub versions of tessera-core tables in the test
# database for specs that test read-only ActiveRecord models.
#
# IMPORTANT: These tables are TEST-ONLY. In production, tessera-core (Elixir/
# Phoenix) owns and manages these tables. MerchantHub NEVER runs migrations
# against them. This setup file exists solely so the test suite can exercise
# the read-only AR models without a live tessera-core database.

RSpec.configure do |config|
  config.before(:suite) do
    conn = ActiveRecord::Base.connection

    unless conn.table_exists?(:payments)
      conn.create_table :payments, id: :uuid, force: :cascade do |t|
        t.string :shop_id, null: false
        t.string :status, null: false
        t.bigint :amount, null: false
        t.string :currency, null: false
        t.string :idempotency_key
        t.string :merchant_reference
        t.datetime :inserted_at, null: false
        t.datetime :updated_at, null: false
      end
    end

    unless conn.table_exists?(:audit_events)
      conn.create_table :audit_events, id: :uuid, force: :cascade do |t|
        t.uuid :payment_id, null: false
        t.string :event_type, null: false
        t.string :actor
        t.string :outcome
        t.jsonb :metadata, default: {}
        t.datetime :occurred_at, null: false
      end
    end

    unless conn.table_exists?(:webhook_deliveries)
      conn.create_table :webhook_deliveries, id: :uuid, force: :cascade do |t|
        t.uuid :payment_id, null: false
        t.string :status, null: false
        t.integer :attempts, default: 0, null: false
        t.datetime :last_attempted_at
        t.datetime :delivered_at
      end
    end

    unless conn.table_exists?(:merchants)
      conn.create_table :merchants, id: :uuid, force: :cascade do |t|
        t.string :merchant_id, null: false
        t.string :name, null: false
        t.string :company_name
        t.string :country
        t.datetime :inserted_at, null: false
        t.datetime :updated_at, null: false
      end
    end

    unless conn.table_exists?(:shops)
      conn.create_table :shops, id: :uuid, force: :cascade do |t|
        t.string :shop_id, null: false
        t.string :merchant_id, null: false
        t.string :name, null: false
        t.string :notification_url
        t.boolean :test_mode, default: false, null: false
        t.string :country
        t.datetime :inserted_at, null: false
        t.datetime :updated_at, null: false
      end
    end
  end

  config.after(:suite) do
    conn = ActiveRecord::Base.connection
    conn.drop_table :webhook_deliveries, if_exists: true
    conn.drop_table :audit_events, if_exists: true
    conn.drop_table :payments, if_exists: true
    conn.drop_table :shops, if_exists: true
    conn.drop_table :merchants, if_exists: true
  end
end
