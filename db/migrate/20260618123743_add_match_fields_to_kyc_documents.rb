class AddMatchFieldsToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_documents, :match_method, :string
    add_column :kyc_documents, :match_confidence, :decimal, precision: 4, scale: 3
  end
end
