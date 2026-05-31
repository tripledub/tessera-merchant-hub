class CreateShops < ActiveRecord::Migration[8.1]
  def change
    create_table :shops do |t|
      t.string :shop_id, null: false
      t.string :name, null: false
      t.string :notification_url
      t.boolean :test_mode, null: false, default: false

      t.timestamps
    end
    add_index :shops, :shop_id, unique: true
  end
end
