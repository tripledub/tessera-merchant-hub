# frozen_string_literal: true

# MH-199: adds a lightweight "this document has been replaced" concept to
# KycDocument. Nothing in the codebase prior to this migration distinguishes
# an old, expired document from a newer replacement of the same type sitting
# alongside it in the same table (Onboarding::DocumentCollectionService#item_received?
# and MH-198's completeness/readiness queries both treat ANY matching
# document as satisfying, with no recency concept). This column is the
# minimal, additive fix: nullable, self-referential, set only when a
# replacement is confirmed (see Kyc::DocumentExpiryMonitoringJob).
class AddSupersededByToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_documents, :superseded_by_kyc_document_id, :uuid
    add_index :kyc_documents, :superseded_by_kyc_document_id
    add_foreign_key :kyc_documents, :kyc_documents, column: :superseded_by_kyc_document_id
  end
end
