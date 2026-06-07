# frozen_string_literal: true

class CreateMerchantsAndShops < ActiveRecord::Migration[8.1]
  # ADR-007: MerchantHub owns merchant/shop admin data. tessera-core owns
  # integration accounts and credentials only (linked by integration_account_id).
  def change
    create_table :merchants, id: :uuid do |t|
      t.string :merchant_id, null: false
      t.string :name, null: false
      t.string :company_name
      t.string :country

      t.timestamps
    end
    add_index :merchants, :merchant_id, unique: true

    create_table :shops, id: :uuid do |t|
      t.string :shop_id, null: false
      t.string :merchant_id, null: false
      t.string :integration_account_id, null: false
      t.string :name, null: false
      t.string :notification_url
      t.boolean :test_mode, null: false, default: false
      t.string :country

      t.timestamps
    end
    add_index :shops, :shop_id, unique: true
    add_index :shops, :merchant_id
    add_index :shops, :integration_account_id
  end
end
