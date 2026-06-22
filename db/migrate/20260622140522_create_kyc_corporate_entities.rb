# frozen_string_literal: true

class CreateKycCorporateEntities < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_corporate_entities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :applicant_id, null: false
      t.uuid :kyc_document_id, null: false
      t.string :name, null: false
      t.integer :entity_type, null: false
      t.string :jurisdiction

      t.timestamps
    end

    add_index :kyc_corporate_entities, :applicant_id
    add_index :kyc_corporate_entities, :kyc_document_id
    add_foreign_key :kyc_corporate_entities, :merchants, column: :applicant_id
    add_foreign_key :kyc_corporate_entities, :kyc_documents
  end
end
