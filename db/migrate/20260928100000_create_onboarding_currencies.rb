# frozen_string_literal: true

class CreateOnboardingCurrencies < ActiveRecord::Migration[8.0]
  def change
    create_table :onboarding_currencies, id: :uuid do |t|
      t.references :onboarding_application, null: false, foreign_key: true, type: :uuid
      t.integer :kind, null: false
      t.string :code, null: false
      t.timestamps
    end

    add_index :onboarding_currencies, %i[onboarding_application_id kind code],
              unique: true, name: "index_onboarding_currencies_on_application_kind_code"
  end
end
