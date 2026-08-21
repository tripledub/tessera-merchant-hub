# frozen_string_literal: true

class CreateRegistryAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :registry_addresses, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :registry_profile_id, null: false
      t.string :kind, null: false
      t.string :line1, null: false
      t.string :city
      t.string :postcode
      t.string :country

      t.timestamps
    end

    add_index :registry_addresses, :registry_profile_id
    add_foreign_key :registry_addresses, :registry_profiles
  end
end
