# frozen_string_literal: true

class CreateKycDocumentValidityPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_document_validity_policies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :document_type, null: false
      t.integer :version, null: false
      t.date :effective_from, null: false
      t.integer :mode, null: false
      t.jsonb :required_dates, null: false, default: []
      t.jsonb :warning_thresholds, null: false, default: []
      t.integer :max_age_months
      t.boolean :blocking, null: false, default: true
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :kyc_document_validity_policies, %i[document_type version], unique: true
    add_index :kyc_document_validity_policies, %i[document_type effective_from]
  end
end
