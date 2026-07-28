# frozen_string_literal: true

# MH-199: stateful (not append-only) tracking of "this document needs to be
# replaced before it expires." Unlike Kyc::DocumentValidityAssessment
# (MH-197, pure historical record), a requirement has genuine mutable state
# — warned -> escalated -> closed — because it represents an ongoing
# obligation, not a point-in-time fact.
#
# A single kyc_document has AT MOST ONE requirement row, ever: once closed
# (via supersession), that document's story is over. If its replacement
# later also approaches expiry, the replacement gets its own, separate
# requirement row keyed to its own id. This is enforced with a plain unique
# index on kyc_document_id (not a partial "only one OPEN" index) — since
# there is only ever one row per document, both are equivalent, but the
# plain index is simpler and also protects against a stray attempt to
# create a second row for an already-closed document.
class CreateKycDocumentReplacementRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :kyc_document_replacement_requirements, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :kyc_document_id, null: false
      t.integer :status, null: false, default: 0
      t.datetime :opened_at, null: false
      t.datetime :escalated_at
      t.datetime :closed_at
      t.uuid :superseded_by_kyc_document_id

      t.timestamps
    end

    add_index :kyc_document_replacement_requirements, :kyc_document_id, unique: true
    add_foreign_key :kyc_document_replacement_requirements, :kyc_documents
    add_foreign_key :kyc_document_replacement_requirements, :kyc_documents,
                     column: :superseded_by_kyc_document_id
  end
end
