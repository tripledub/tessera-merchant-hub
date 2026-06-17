# frozen_string_literal: true

class Applicant < Merchant
  has_many :kyc_principals, foreign_key: :applicant_id, inverse_of: :applicant, dependent: :destroy
  has_many :kyc_documents,  foreign_key: :applicant_id, inverse_of: :applicant, dependent: :destroy

  validates :merchant_id, absence: true
  validates :name, presence: true
  validates :contact_email,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    allow_blank: true

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected" }, default: "pending"

  def to_param
    id
  end
end
