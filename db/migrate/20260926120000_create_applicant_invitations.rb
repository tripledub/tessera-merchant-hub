# frozen_string_literal: true

class CreateApplicantInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :applicant_invitations, id: :uuid do |t|
      t.references :applicant, null: false, foreign_key: { to_table: :merchants }, type: :uuid
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.references :claimed_by, null: true, foreign_key: { to_table: :applicant_users }, type: :uuid
      t.string :email, null: false
      t.string :token_digest, null: false
      t.datetime :claimed_at
      t.datetime :submitted_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :applicant_invitations, :token_digest, unique: true
  end
end
