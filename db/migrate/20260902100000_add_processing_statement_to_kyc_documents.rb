# frozen_string_literal: true

class AddProcessingStatementToKycDocuments < ActiveRecord::Migration[8.0]
  def change
    add_reference :kyc_documents, :processing_statement, type: :uuid, foreign_key: true, index: { unique: true }
  end
end
