# frozen_string_literal: true

class CreateRegistryPeopleWithSignificantControl < ActiveRecord::Migration[8.1]
  def change
    create_table :registry_people_with_significant_control, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :registry_profile_id, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.string :natures_of_control, array: true, null: false, default: []
      t.date :notified_on
      t.date :ceased_on
      t.string :nationality
      t.integer :date_of_birth_month
      t.integer :date_of_birth_year
      t.string :line1
      t.string :city
      t.string :postcode
      t.string :country

      t.timestamps
    end

    add_index :registry_people_with_significant_control, :registry_profile_id,
              name: "index_registry_people_wsc_on_registry_profile_id"
    add_foreign_key :registry_people_with_significant_control, :registry_profiles
  end
end
