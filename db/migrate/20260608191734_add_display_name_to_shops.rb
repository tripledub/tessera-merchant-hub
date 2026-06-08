class AddDisplayNameToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :display_name, :string
  end
end
