class CreateApplicantDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :applicant_domains, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :applicant, null: false, foreign_key: { to_table: :merchants }, type: :uuid
      t.string :name, null: false
      t.integer :verification_status, null: false, default: 0
      t.timestamps
    end

    add_index :applicant_domains, "applicant_id, lower(name)", unique: true, name: "index_applicant_domains_on_applicant_id_and_lower_name"
  end
end
