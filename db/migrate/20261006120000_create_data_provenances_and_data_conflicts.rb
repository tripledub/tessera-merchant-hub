# frozen_string_literal: true

# MH-389: where each piece of application data came from, and where sources disagree.
class CreateDataProvenancesAndDataConflicts < ActiveRecord::Migration[8.0]
  def change
    create_table :data_provenances, id: :uuid do |t|
      t.references :applicant, null: false, type: :uuid, foreign_key: { to_table: :merchants }
      t.string :record_type, null: false
      t.string :record_id, null: false
      # "" for a whole record (a principal), a column name for a single field.
      t.string :field, null: false, default: ""
      t.integer :source, null: false, default: 0
      t.string :provider
      t.datetime :retrieved_at
      t.text :previous_value
      t.timestamps
    end

    add_index :data_provenances, %i[record_type record_id field],
              unique: true, name: "index_data_provenances_on_record_and_field"

    create_table :data_conflicts, id: :uuid do |t|
      t.references :applicant, null: false, type: :uuid, foreign_key: { to_table: :merchants }
      t.string :record_type, null: false
      t.string :record_id, null: false
      t.string :field, null: false
      t.text :held_value
      t.integer :held_source, null: false, default: 0
      t.string :held_provider
      t.text :proposed_value
      t.integer :proposed_source, null: false, default: 0
      t.string :proposed_provider
      t.integer :status, null: false, default: 0
      t.datetime :detected_at, null: false
      t.timestamps
    end

    add_index :data_conflicts, %i[applicant_id status]
    # One open conflict per field; a repeat detection updates it instead of piling up.
    add_index :data_conflicts, %i[record_type record_id field],
              unique: true, where: "status = 0", name: "index_data_conflicts_on_open_record_field"
  end
end
