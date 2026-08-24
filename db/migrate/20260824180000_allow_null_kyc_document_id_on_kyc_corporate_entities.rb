# frozen_string_literal: true

class AllowNullKycDocumentIdOnKycCorporateEntities < ActiveRecord::Migration[8.1]
  def change
    change_column_null :kyc_corporate_entities, :kyc_document_id, true
  end
end
