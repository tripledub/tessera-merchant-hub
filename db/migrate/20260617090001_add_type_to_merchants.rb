class AddTypeToMerchants < ActiveRecord::Migration[8.1]
  def change
    add_column :merchants, :type, :string
    add_column :merchants, :status, :string, null: false, default: "pending"
    change_column_null :merchants, :merchant_id, true
    remove_index :merchants, :merchant_id
    add_index :merchants, :merchant_id, unique: true, where: "merchant_id IS NOT NULL"
    add_index :merchants, :type
  end
end
