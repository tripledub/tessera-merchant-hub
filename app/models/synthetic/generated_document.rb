# frozen_string_literal: true

module Synthetic
  # MH-309: a record of one document generated for a persona — the acting
  # user and the options used — shown on the persona's page and doubling as
  # the audit trail the gated generation endpoint is required to keep.
  class GeneratedDocument < ApplicationRecord
    self.table_name = "synthetic_generated_documents"

    belongs_to :synthetic_persona, class_name: "Synthetic::Persona", inverse_of: :generated_documents
    belongs_to :generated_by, class_name: "User"

    validates :document_type, presence: true
  end
end
