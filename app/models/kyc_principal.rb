# frozen_string_literal: true

class KycPrincipal < ApplicationRecord
  belongs_to :applicant, foreign_key: :applicant_id, inverse_of: :kyc_principals
  has_many :kyc_documents, foreign_key: :kyc_principal_id, inverse_of: :kyc_principal, dependent: :nullify

  # unspecified (MH-307): the role a principal gets when created from an
  # identity document alone, with no registry or company-document evidence
  # of what they actually are. Appended, not inserted, so existing rows keep
  # their integer values. Never the DEFAULT for the column/enum — that stays
  # :director so any caller that (like the registry and manual-entry paths)
  # already sets a real role explicitly is unaffected; only
  # PrincipalMatcherService's passport-only auto-creation path passes
  # role: :unspecified.
  enum :role, { director: 0, psc: 1, director_and_psc: 2, shareholder: 3, secretary: 4, unspecified: 5 },
    default: :director
  enum :status, { unconfirmed: 0, confirmed: 1 }, default: :confirmed
  enum :source, { document_extracted: 0, applicant_declared: 1, registry_fetched: 2 }, default: :document_extracted

  validates :name, presence: true
end
