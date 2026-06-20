# frozen_string_literal: true

class AddExtractedDataToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_documents, :extracted_data, :jsonb, default: {}
  end
end
