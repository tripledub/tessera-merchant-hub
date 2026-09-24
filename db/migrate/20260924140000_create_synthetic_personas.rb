# frozen_string_literal: true

# MH-309: the reusable, persisted unit for generating synthetic (fake) KYC
# test documents. Gated entirely at the controller/UI layer by the existing
# SYNTHETIC_DATA_ENABLED flag (config/initializers/synthetic_data.rb,
# introduced for MH-310) — this migration itself carries no gate.
class CreateSyntheticPersonas < ActiveRecord::Migration[8.1]
  def change
    create_table :synthetic_personas, id: :uuid do |t|
      t.string :slug, null: false
      t.string :given_names, null: false
      t.string :surname, null: false
      t.date :date_of_birth, null: false
      t.string :sex, null: false, default: "unspecified"
      t.string :jurisdiction, null: false, default: "xu"

      t.timestamps
    end

    add_index :synthetic_personas, :slug, unique: true
  end
end
