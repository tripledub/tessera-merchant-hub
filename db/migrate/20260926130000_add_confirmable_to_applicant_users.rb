# frozen_string_literal: true

class AddConfirmableToApplicantUsers < ActiveRecord::Migration[8.0]
  def change
    change_table :applicant_users, bulk: true do |t|
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email
    end

    add_index :applicant_users, :confirmation_token, unique: true

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE applicant_users
          SET confirmed_at = CURRENT_TIMESTAMP
          WHERE confirmed_at IS NULL
        SQL
      end
    end
  end
end
