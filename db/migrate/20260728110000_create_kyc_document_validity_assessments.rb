# frozen_string_literal: true

class CreateKycDocumentValidityAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_document_validity_assessments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :kyc_document_id, null: false
      t.uuid :kyc_document_validity_policy_id, null: false
      t.integer :policy_version, null: false
      t.datetime :assessed_at, null: false
      t.date :reference_date, null: false
      t.jsonb :dates_used, null: false, default: {}
      t.integer :outcome, null: false
      t.string :reason_code, null: false
      t.jsonb :reason_details

      t.timestamps
    end

    add_index :kyc_document_validity_assessments, %i[kyc_document_id assessed_at]
    add_foreign_key :kyc_document_validity_assessments, :kyc_documents
    add_foreign_key :kyc_document_validity_assessments, :kyc_document_validity_policies
  end
end
