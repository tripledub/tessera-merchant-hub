# frozen_string_literal: true

class AddCommentStatusToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_documents, :comment_status, :integer
  end
end
