# frozen_string_literal: true

class AddValidityDatesToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_documents, :validity_dates, :jsonb, null: false, default: {}
    add_column :kyc_documents, :validity_confirmation_required, :boolean, null: false, default: false
  end
end
