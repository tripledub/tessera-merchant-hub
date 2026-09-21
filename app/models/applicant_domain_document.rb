# frozen_string_literal: true

# One piece of evidence for a domain: a proof-of-domain document that shows the
# applicant owns it. Created by extraction (Kyc::DomainEvidenceRecorder) or
# attached by hand from the Domains tab.
class ApplicantDomainDocument < ApplicationRecord
  belongs_to :applicant_domain
  belongs_to :kyc_document

  validates :kyc_document_id, uniqueness: { scope: :applicant_domain_id }
  validate :document_belongs_to_domains_applicant
  validate :document_is_proof_of_domain, on: :create

  private

  def document_belongs_to_domains_applicant
    return unless applicant_domain && kyc_document
    return if kyc_document.applicant_id == applicant_domain.applicant_id

    errors.add(:kyc_document, "must belong to the same applicant as the domain")
  end

  # Only checked on create: reclassifying the document later shouldn't
  # invalidate a link a reviewer already relied on.
  def document_is_proof_of_domain
    return unless kyc_document
    return if kyc_document.proof_of_domain_ownership?

    errors.add(:kyc_document, "must be a proof of domain ownership document")
  end
end
