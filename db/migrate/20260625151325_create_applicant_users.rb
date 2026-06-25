# frozen_string_literal: true

class CreateApplicantUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :applicant_users, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :applicant, null: false, foreign_key: { to_table: :merchants }, type: :uuid

      t.string :email,              null: false
      t.string :encrypted_password, null: false, default: ""
      t.string :first_name
      t.string :last_name

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      t.timestamps
    end

    add_index :applicant_users, :email,                unique: true
    add_index :applicant_users, :reset_password_token, unique: true
  end
end
