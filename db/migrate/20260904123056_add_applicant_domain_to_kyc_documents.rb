class AddApplicantDomainToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_reference :kyc_documents, :applicant_domain, type: :uuid, foreign_key: true, null: true
  end
end
