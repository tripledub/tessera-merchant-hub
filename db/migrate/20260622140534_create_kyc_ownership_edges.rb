# frozen_string_literal: true

class CreateKycOwnershipEdges < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_ownership_edges, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :parent_entity_id, null: false
      t.uuid :child_entity_id, null: false
      t.integer :relationship_type, null: false
      t.decimal :percentage, precision: 5, scale: 2
      t.uuid :source_document_id

      t.timestamps
    end

    add_index :kyc_ownership_edges, :parent_entity_id
    add_index :kyc_ownership_edges, :child_entity_id
    add_index :kyc_ownership_edges, :source_document_id
    add_foreign_key :kyc_ownership_edges, :kyc_corporate_entities, column: :parent_entity_id
    add_foreign_key :kyc_ownership_edges, :kyc_corporate_entities, column: :child_entity_id
    add_foreign_key :kyc_ownership_edges, :kyc_documents, column: :source_document_id
  end
end
