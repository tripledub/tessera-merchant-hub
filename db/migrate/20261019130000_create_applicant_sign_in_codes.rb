# frozen_string_literal: true

# MH-404: one-time sign-in codes emailed to an applicant's address. Keyed by
# applicant and email, not by user: a first-time invitee has no user yet. Only a
# keyed digest of the code is stored, never the code itself.
class CreateApplicantSignInCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :applicant_sign_in_codes, id: :uuid do |t|
      t.references :applicant, null: false, type: :uuid, foreign_key: { to_table: :merchants }
      t.references :applicant_invitation, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :applicant_user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :email, null: false
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :consumed_at
      t.datetime :invalidated_at
      t.timestamps
    end

    add_index :applicant_sign_in_codes, %i[applicant_id email created_at],
              name: "index_applicant_sign_in_codes_on_applicant_email_and_time"
  end
end
