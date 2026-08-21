# frozen_string_literal: true

class CreateRegistryDirectors < ActiveRecord::Migration[8.1]
  def change
    create_table :registry_directors, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :registry_profile_id, null: false
      t.string :name, null: false
      t.string :role, null: false
      t.date :appointed_on
      t.date :resigned_on

      t.timestamps
    end

    add_index :registry_directors, :registry_profile_id
    add_foreign_key :registry_directors, :registry_profiles
  end
end
