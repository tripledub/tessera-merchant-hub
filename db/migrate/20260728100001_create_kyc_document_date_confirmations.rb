# frozen_string_literal: true

class CreateKycDocumentDateConfirmations < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_document_date_confirmations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :kyc_document_id, null: false
      t.string :date_role, null: false
      t.date :extracted_value
      t.date :confirmed_value, null: false
      t.text :reason
      t.bigint :confirmed_by_id, null: false

      t.timestamps
    end

    add_index :kyc_document_date_confirmations, %i[kyc_document_id date_role]
    add_foreign_key :kyc_document_date_confirmations, :kyc_documents
    add_foreign_key :kyc_document_date_confirmations, :users, column: :confirmed_by_id
  end
end
