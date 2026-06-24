class AddCorporateEntityIdToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_documents, :corporate_entity_id, :uuid
    add_index :kyc_documents, :corporate_entity_id
    add_foreign_key :kyc_documents, :kyc_corporate_entities, column: :corporate_entity_id
  end
end
