# frozen_string_literal: true

# This support file ensures tessera-core read-only tables exist in the test DB.
#
# IMPORTANT: Only tables owned by tessera-core are managed here.
# - payments, audit_events, webhook_deliveries → tessera-core owned (stub created here)
# - merchants, shops, users → MerchantHub owned (created by normal Rails migrations)
#
# In production, tessera-core (Elixir/Phoenix) owns and migrates the stub tables.
# The dev/test stub migration (20260606120000) creates them locally. This before/after
# hook is a belt-and-suspenders guard for the test environment only.

TESSERA_CORE_STUB_TABLES = %w[payments audit_events webhook_deliveries].freeze

RSpec.configure do |config|
  config.before(:suite) do
    conn = ActiveRecord::Base.connection

    unless conn.table_exists?(:payments)
      conn.create_table :payments, id: :uuid, force: :cascade do |t|
        t.string   :shop_id,            null: false
        t.string   :status,             null: false
        t.bigint   :amount,             null: false
        t.string   :currency,           null: false
        t.string   :idempotency_key
        t.string   :merchant_reference
        t.datetime :inserted_at,        null: false, default: -> { "NOW()" }
        t.datetime :updated_at,         null: false, default: -> { "NOW()" }
      end
      conn.add_index :payments, :shop_id
      conn.add_index :payments, :inserted_at
    end

    unless conn.table_exists?(:audit_events)
      conn.create_table :audit_events, id: :uuid, force: :cascade do |t|
        t.uuid     :payment_id,   null: false
        t.string   :event_type,   null: false
        t.string   :actor
        t.string   :outcome
        t.jsonb    :metadata,     null: false, default: {}
        t.datetime :occurred_at,  null: false, default: -> { "NOW()" }
      end
      conn.add_index :audit_events, :payment_id
    end

    unless conn.table_exists?(:webhook_deliveries)
      conn.create_table :webhook_deliveries, id: :uuid, force: :cascade do |t|
        t.uuid     :payment_id,        null: false
        t.string   :status,            null: false
        t.integer  :attempts,          null: false, default: 0
        t.datetime :last_attempted_at
        t.datetime :delivered_at
      end
      conn.add_index :webhook_deliveries, :payment_id
    end
  end

  config.after(:suite) do
    conn = ActiveRecord::Base.connection
    # Only clean up tessera-core stub tables — never touch MH-owned tables.
    conn.drop_table :webhook_deliveries, if_exists: true
    conn.drop_table :audit_events,       if_exists: true
    conn.drop_table :payments,           if_exists: true
  end
end
