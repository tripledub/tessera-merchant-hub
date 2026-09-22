# frozen_string_literal: true

# MH-303: Companies House publishes each officer's month and year of birth
# on the same officers endpoint we already fetch directors from. Mirrors the
# columns already used for registry_people_with_significant_control.
class AddDateOfBirthToRegistryDirectors < ActiveRecord::Migration[8.1]
  def change
    add_column :registry_directors, :date_of_birth_month, :integer
    add_column :registry_directors, :date_of_birth_year, :integer
  end
end
