# frozen_string_literal: true

# Creates read-only stub versions of tessera-core tables in the local
# development database. In production these tables are owned and migrated
# exclusively by tessera-core (Elixir/Phoenix) on the shared Postgres cluster.
#
# MerchantHub NEVER writes to or migrates these tables in any environment.
# This migration is a no-op in production so it is safe to run everywhere.
class CreateTesseraCoreStubTables < ActiveRecord::Migration[8.1]
  def up
    return if Rails.env.production?

    unless table_exists?(:payments)
      create_table :payments, id: :uuid do |t|
        t.string   :shop_id,            null: false
        t.string   :status,             null: false
        t.bigint   :amount,             null: false
        t.string   :currency,           null: false
        t.string   :idempotency_key
        t.string   :merchant_reference
        t.datetime :inserted_at,        null: false, default: -> { "NOW()" }
        t.datetime :updated_at,         null: false, default: -> { "NOW()" }
      end
      add_index :payments, :shop_id
      add_index :payments, :status
      add_index :payments, :inserted_at
    end

    unless table_exists?(:audit_events)
      create_table :audit_events, id: :uuid do |t|
        t.uuid     :payment_id,   null: false
        t.string   :event_type,   null: false
        t.string   :actor
        t.string   :outcome
        t.jsonb    :metadata,     null: false, default: {}
        t.datetime :occurred_at,  null: false, default: -> { "NOW()" }
      end
      add_index :audit_events, :payment_id
    end

    unless table_exists?(:webhook_deliveries)
      create_table :webhook_deliveries, id: :uuid do |t|
        t.uuid     :payment_id,        null: false
        t.string   :status,            null: false
        t.integer  :attempts,          null: false, default: 0
        t.datetime :last_attempted_at
        t.datetime :delivered_at
      end
      add_index :webhook_deliveries, :payment_id
    end
  end

  def down
    return if Rails.env.production?

    drop_table :webhook_deliveries, if_exists: true
    drop_table :audit_events,       if_exists: true
    drop_table :payments,           if_exists: true
  end
end
