# frozen_string_literal: true

class KycDocument < ApplicationRecord
  belongs_to :applicant,     foreign_key: :applicant_id,     inverse_of: :kyc_documents
  belongs_to :kyc_principal, foreign_key: :kyc_principal_id, inverse_of: :kyc_documents, optional: true

  has_one_attached :file

  enum :status, { pending: 0, processing: 1, complete: 2, error: 3 }, default: :pending

  validates :file, presence: true
end
