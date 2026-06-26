# frozen_string_literal: true

class CreateOnboardingMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_messages, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :onboarding_session, null: false, foreign_key: true, type: :uuid

      t.integer :role, null: false
      t.text :content, null: false
      t.string :stage
      t.jsonb :structured_data, null: false, default: {}

      t.timestamps
    end
  end
end
