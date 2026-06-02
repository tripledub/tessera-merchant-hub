class RenameUsersShopIdToMerchantId < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :shop_id, :merchant_id
    rename_index :users, "index_users_on_shop_id", "index_users_on_merchant_id" if index_name_exists?(:users, "index_users_on_shop_id")
  end
end
