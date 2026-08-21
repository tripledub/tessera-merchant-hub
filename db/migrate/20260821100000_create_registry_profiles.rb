# frozen_string_literal: true

class CreateRegistryProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :registry_profiles, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :applicant_id, null: false
      t.string :jurisdiction, null: false
      t.string :company_number, null: false
      t.string :company_name, null: false
      t.string :status
      t.date :incorporated_on
      t.datetime :fetched_at, null: false
      t.jsonb :raw_response, null: false, default: {}

      t.timestamps
    end

    add_index :registry_profiles, :applicant_id
    add_foreign_key :registry_profiles, :merchants, column: :applicant_id
  end
end
