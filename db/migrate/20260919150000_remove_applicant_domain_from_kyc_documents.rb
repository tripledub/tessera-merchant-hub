class RemoveApplicantDomainFromKycDocuments < ActiveRecord::Migration[8.1]
  # MH-296: domains are extracted from proof-of-domain documents and reviewed
  # on the Domains tab (MH-295), so a document no longer links to a domain.
  def change
    remove_reference :kyc_documents, :applicant_domain, type: :uuid, foreign_key: true, index: true
  end
end
