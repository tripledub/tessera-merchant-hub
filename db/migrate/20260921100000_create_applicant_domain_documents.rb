class CreateApplicantDomainDocuments < ActiveRecord::Migration[8.1]
  # MH-299: a domain can be evidenced by several documents (and a document can
  # evidence several domains), so the single applicant_domains.source_document_id
  # from MH-295 becomes a join table. Existing links are carried across.
  def up
    create_table :applicant_domain_documents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :applicant_domain, null: false, type: :uuid, index: false,
                   foreign_key: { on_delete: :cascade }
      t.references :kyc_document, null: false, type: :uuid,
                   foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :applicant_domain_documents, %i[applicant_domain_id kyc_document_id], unique: true,
              name: "index_applicant_domain_documents_on_domain_and_document"

    execute <<~SQL.squish
      INSERT INTO applicant_domain_documents (applicant_domain_id, kyc_document_id, created_at, updated_at)
      SELECT id, source_document_id, NOW(), NOW()
      FROM applicant_domains
      WHERE source_document_id IS NOT NULL
    SQL

    remove_reference :applicant_domains, :source_document, type: :uuid, index: true,
                     foreign_key: { to_table: :kyc_documents, on_delete: :nullify }
  end

  # Lossy by nature: a domain with several evidence documents keeps only the
  # earliest as its single source.
  def down
    add_reference :applicant_domains, :source_document, type: :uuid, null: true, index: true,
                  foreign_key: { to_table: :kyc_documents, on_delete: :nullify }

    execute <<~SQL.squish
      UPDATE applicant_domains d
      SET source_document_id = (
        SELECT l.kyc_document_id FROM applicant_domain_documents l
        WHERE l.applicant_domain_id = d.id
        ORDER BY l.created_at, l.id LIMIT 1
      )
    SQL

    drop_table :applicant_domain_documents
  end
end
