# frozen_string_literal: true

class CreateOnboardingCountries < ActiveRecord::Migration[8.0]
  STEPS_AFTER_COUNTRIES = %w[principals review].freeze

  def up
    create_table :onboarding_countries, id: :uuid do |t|
      t.references :onboarding_application, null: false, foreign_key: true, type: :uuid
      t.string :code, null: false
      t.timestamps
    end

    add_index :onboarding_countries, %i[onboarding_application_id code],
              unique: true, name: "index_onboarding_countries_on_application_and_code"

    route_drafts_through_countries
  end

  def down
    drop_table :onboarding_countries
  end

  # Drafts that already moved past the (previously empty) countries step have no
  # selection, so send them back to pick one before they can submit.
  def route_drafts_through_countries
    quoted_steps = STEPS_AFTER_COUNTRIES.map { |step| connection.quote(step) }.join(", ")
    execute <<~SQL.squish
      UPDATE onboarding_applications
      SET current_step = 'countries'
      WHERE status = 0
        AND current_step IN (#{quoted_steps})
    SQL
  end
end
