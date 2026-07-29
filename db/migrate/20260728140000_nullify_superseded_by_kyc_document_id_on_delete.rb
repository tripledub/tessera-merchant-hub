# frozen_string_literal: true

# MH-199 fix: the self-referential FK added in
# 20260728120000_add_superseded_by_to_kyc_documents.rb had no `on_delete`
# behavior, defaulting to Postgres RESTRICT. An applicant with one document
# superseded by another (both belonging to that applicant) could not be
# deleted: Applicant#kyc_documents is `dependent: :destroy`, and Rails
# destroys the associated kyc_documents individually in arbitrary order. If
# the newer (referenced) document is destroyed before the older (referencing)
# one, Postgres raises ActiveRecord::InvalidForeignKey because the old
# document's superseded_by_kyc_document_id still points at it.
#
# Switching to `on_delete: :nullify` lets Postgres automatically null out
# any row's superseded_by_kyc_document_id when the document it points to is
# deleted, so deletion order no longer matters.
class NullifySupersededByKycDocumentIdOnDelete < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :kyc_documents, :kyc_documents, column: :superseded_by_kyc_document_id
    add_foreign_key :kyc_documents, :kyc_documents, column: :superseded_by_kyc_document_id, on_delete: :nullify
  end
end
