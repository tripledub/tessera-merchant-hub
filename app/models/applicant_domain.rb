# frozen_string_literal: true

class ApplicantDomain < ApplicationRecord
  DOMAIN_FORMAT = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/i

  belongs_to :applicant, foreign_key: :applicant_id, inverse_of: :applicant_domains
  has_many :kyc_documents, foreign_key: :applicant_domain_id, inverse_of: :applicant_domain, dependent: :nullify

  enum :verification_status, { unverified: 0, verified: 1 }, default: :unverified

  validates :name, presence: true, format: { with: DOMAIN_FORMAT }, uniqueness: { scope: :applicant_id, case_sensitive: false }
end
