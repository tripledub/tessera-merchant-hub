# frozen_string_literal: true

class AddSectorToMerchants < ActiveRecord::Migration[8.0]
  def change
    add_column :merchants, :sector, :string, null: false, default: "general"
  end
end
