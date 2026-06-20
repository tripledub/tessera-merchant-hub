# frozen_string_literal: true

class AddDocumentTypeAndClassificationToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_documents, :document_type, :integer
    add_column :kyc_documents, :classification_status, :integer, default: 0, null: false
    add_column :kyc_documents, :classification_confidence, :float
    add_column :kyc_documents, :classification_method, :string
  end
end
