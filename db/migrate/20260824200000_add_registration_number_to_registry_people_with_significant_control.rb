# frozen_string_literal: true

class AddRegistrationNumberToRegistryPeopleWithSignificantControl < ActiveRecord::Migration[8.1]
  def change
    add_column :registry_people_with_significant_control, :registration_number, :string
  end
end
