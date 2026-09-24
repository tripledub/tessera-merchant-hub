# frozen_string_literal: true

# MH-309: a record of each document generated for a Synthetic::Persona — the
# acting user, the document type and the options used. Doubles as the "which
# documents have been generated for each persona" history shown on the
# persona page (AC5) and the audit log the gated generation endpoint must
# write (see the "Gate and access" section of MH-309).
class CreateSyntheticGeneratedDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :synthetic_generated_documents, id: :uuid do |t|
      t.references :synthetic_persona, null: false, foreign_key: true, type: :uuid
      t.references :generated_by, null: false, foreign_key: { to_table: :users }
      t.string :document_type, null: false
      t.jsonb :options, null: false, default: {}

      t.timestamps
    end
  end
end
