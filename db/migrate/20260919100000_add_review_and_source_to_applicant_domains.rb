class AddReviewAndSourceToApplicantDomains < ActiveRecord::Migration[8.1]
  # Defaults are the backfill: every existing row was added by hand, so it
  # reads as an already-accepted manual domain (review_status 1, source 0).
  def change
    add_column :applicant_domains, :review_status, :integer, null: false, default: 1
    add_column :applicant_domains, :source, :integer, null: false, default: 0
    add_reference :applicant_domains, :source_document, type: :uuid, null: true,
                  foreign_key: { to_table: :kyc_documents, on_delete: :nullify }
  end
end
