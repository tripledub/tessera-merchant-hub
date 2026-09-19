# frozen_string_literal: true

class ApplicantDomain < ApplicationRecord
  DOMAIN_FORMAT = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/i

  belongs_to :applicant, foreign_key: :applicant_id, inverse_of: :applicant_domains
  has_many :kyc_documents, foreign_key: :applicant_domain_id, inverse_of: :applicant_domain, dependent: :nullify
  belongs_to :source_document, class_name: "KycDocument", optional: true, inverse_of: :extracted_domains

  enum :verification_status, { unverified: 0, verified: 1 }, default: :unverified

  # Extracted domains start `pending` and need a psp_admin's accept/reject;
  # hand-added ones are accepted on creation (the column default). Rejected
  # rows are kept so re-extraction never resurrects them.
  enum :review_status, { pending: 0, accepted: 1, rejected: 2 }, default: :accepted
  enum :source, { manual: 0, extracted: 1 }, default: :manual, prefix: :source

  validates :name, presence: true, format: { with: DOMAIN_FORMAT }, uniqueness: { scope: :applicant_id, case_sensitive: false }
end
