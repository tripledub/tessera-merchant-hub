# frozen_string_literal: true

class CreateOnboardingApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :onboarding_applications, id: :uuid do |t|
      t.references :applicant, null: false, foreign_key: { to_table: :merchants }, type: :uuid, index: { unique: true }
      t.string :current_step, null: false, default: "company"
      t.string :completed_steps, array: true, null: false, default: []
      t.integer :status, null: false, default: 0
      t.datetime :submitted_at

      t.timestamps
    end
  end
end
