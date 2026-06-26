# frozen_string_literal: true

class CreateOnboardingSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_sessions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :applicant, null: false, foreign_key: { to_table: :merchants }, type: :uuid,
        index: { unique: true }

      t.integer :current_stage, null: false, default: 0
      t.string :completed_stages, null: false, array: true, default: []
      t.jsonb :stage_data, null: false, default: {}
      t.jsonb :document_checklist, null: false, default: {}
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
