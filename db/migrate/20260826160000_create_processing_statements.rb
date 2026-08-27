# frozen_string_literal: true

class CreateProcessingStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :processing_statements, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :applicant, null: false, foreign_key: { to_table: :merchants }, type: :uuid
      t.integer :status, null: false, default: 0
      t.jsonb :column_mapping, null: false, default: {}
      t.jsonb :metrics, null: false, default: {}
      t.integer :row_count
      t.text :error_message

      t.timestamps
    end
  end
end
