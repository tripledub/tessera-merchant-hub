# frozen_string_literal: true

class AllowNullKycDocumentIdOnKycValidationWarnings < ActiveRecord::Migration[8.1]
  def change
    change_column_null :kyc_validation_warnings, :kyc_document_id, true
  end
end
