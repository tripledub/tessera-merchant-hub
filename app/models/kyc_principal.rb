# frozen_string_literal: true

class KycPrincipal < ApplicationRecord
  belongs_to :applicant, foreign_key: :applicant_id, inverse_of: :kyc_principals
  has_many :kyc_documents, foreign_key: :kyc_principal_id, inverse_of: :kyc_principal, dependent: :nullify

  enum :role,   { director: 0, psc: 1, director_and_psc: 2, shareholder: 3 }, default: :director
  enum :status, { unconfirmed: 0, confirmed: 1 }, default: :confirmed

  validates :name, presence: true
end
