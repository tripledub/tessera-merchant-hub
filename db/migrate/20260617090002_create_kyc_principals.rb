class CreateKycPrincipals < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_principals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :applicant, null: false, foreign_key: { to_table: :merchants }, type: :uuid
      t.string :name, null: false
      t.integer :role, null: false, default: 0
      t.timestamps
    end
  end
end
