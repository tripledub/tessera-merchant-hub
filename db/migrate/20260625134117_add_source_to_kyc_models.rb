class AddSourceToKycModels < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_principals, :source, :integer, default: 0, null: false
    add_column :kyc_corporate_entities, :source, :integer, default: 0, null: false
    add_column :kyc_ownership_edges, :source, :integer, default: 0, null: false
  end
end
