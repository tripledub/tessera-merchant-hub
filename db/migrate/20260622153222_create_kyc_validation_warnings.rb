# frozen_string_literal: true

class CreateKycValidationWarnings < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_validation_warnings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :applicant_id, null: false
      t.uuid :kyc_document_id, null: false
      t.uuid :corporate_entity_id
      t.integer :warning_type, null: false
      t.string :message, null: false
      t.jsonb :metadata, default: {}
      t.boolean :acknowledged, default: false, null: false

      t.timestamps
    end

    add_index :kyc_validation_warnings, :applicant_id
    add_index :kyc_validation_warnings, :kyc_document_id
    add_index :kyc_validation_warnings, :corporate_entity_id
    add_foreign_key :kyc_validation_warnings, :merchants, column: :applicant_id
    add_foreign_key :kyc_validation_warnings, :kyc_documents
    add_foreign_key :kyc_validation_warnings, :kyc_corporate_entities, column: :corporate_entity_id
  end
end
