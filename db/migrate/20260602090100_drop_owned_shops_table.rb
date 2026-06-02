class DropOwnedShopsTable < ActiveRecord::Migration[8.1]
  # ADR-007: shops are control-plane data owned by tessera-core. MerchantHub
  # reads them via Tessera::Shop instead of owning this table.
  def up
    drop_table :shops, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
