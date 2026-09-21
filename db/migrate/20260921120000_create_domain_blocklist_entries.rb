class CreateDomainBlocklistEntries < ActiveRecord::Migration[8.1]
  # MH-298: registrar and similar domains (GoDaddy etc.) turn up on most
  # proof-of-domain documents and are always rejected, so a psp_admin can list
  # them once and have extraction reject them automatically.
  def up
    create_table :domain_blocklist_entries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.references :created_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :domain_blocklist_entries, "lower(name)", unique: true,
              name: "index_domain_blocklist_entries_on_lower_name"

    # Why a domain was rejected: by a person, or by the blocklist. Nullable, and
    # only set while rejected. Every rejection so far was made by a person.
    add_column :applicant_domains, :rejection_reason, :integer
    execute "UPDATE applicant_domains SET rejection_reason = 0 WHERE review_status = 2"

    # The agreed starting list. Everything else is added through the admin page.
    execute <<~SQL.squish
      INSERT INTO domain_blocklist_entries (name, created_at, updated_at)
      VALUES ('godaddy.com', NOW(), NOW())
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    remove_column :applicant_domains, :rejection_reason
    drop_table :domain_blocklist_entries
  end
end
