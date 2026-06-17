class CreateKycDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_documents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :applicant,     null: false, foreign_key: { to_table: :merchants }, type: :uuid
      t.references :kyc_principal, null: true,  foreign_key: true, type: :uuid
      t.integer :status, null: false, default: 0
      t.jsonb :result
      t.timestamps
    end
  end
end
