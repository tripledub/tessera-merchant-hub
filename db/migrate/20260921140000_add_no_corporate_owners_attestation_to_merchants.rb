class AddNoCorporateOwnersAttestationToMerchants < ActiveRecord::Migration[8.1]
  # MH-251: an empty ownership graph only counts as compliant when staff have
  # explicitly attested the applicant has no corporate owners. Who and when are
  # kept for audit. Columns live on merchants because Applicant is an STI subclass.
  def change
    add_column :merchants, :no_corporate_owners_attested_at, :datetime
    add_reference :merchants, :no_corporate_owners_attested_by, null: true,
                  foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
