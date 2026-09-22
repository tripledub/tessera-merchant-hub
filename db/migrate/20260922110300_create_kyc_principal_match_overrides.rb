# frozen_string_literal: true

# MH-303: audit trail for a reviewer resolving a registry date-of-birth
# mismatch from a document row — either linking the document to the
# mismatched principal anyway, or declaring it a different person (which
# creates a new principal). Append-only, like Kyc::DocumentDateConfirmation.
class CreateKycPrincipalMatchOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_principal_match_overrides, id: :uuid do |t|
      t.references :kyc_document, type: :uuid, null: false, foreign_key: true
      t.references :kyc_principal, type: :uuid, null: false, foreign_key: true
      t.references :resolved_by, null: false, foreign_key: { to_table: :users }
      t.integer :resolution, null: false
      t.text :reason, null: false

      t.timestamps
    end
  end
end
