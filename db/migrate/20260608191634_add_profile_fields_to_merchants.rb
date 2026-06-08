class AddProfileFieldsToMerchants < ActiveRecord::Migration[8.1]
  def change
    add_column :merchants, :contact_email, :string
    add_column :merchants, :support_url, :string
    add_column :merchants, :address_line1, :string
    add_column :merchants, :city, :string
    add_column :merchants, :country_code, :string
  end
end
