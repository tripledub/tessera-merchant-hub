class ChangeUsersShopIdToString < ActiveRecord::Migration[8.1]
  def change
    change_column :users, :shop_id, :string
  end
end
