# frozen_string_literal: true

class AddRegistryFieldsToMerchants < ActiveRecord::Migration[8.1]
  def change
    add_column :merchants, :company_number, :string
    add_column :merchants, :registry_jurisdiction, :string
  end
end
