# frozen_string_literal: true

class Applicant < Merchant
  has_one :onboarding_session, foreign_key: :applicant_id, inverse_of: :applicant, dependent: :destroy

  has_many :kyc_principals, foreign_key: :applicant_id, inverse_of: :applicant, dependent: :destroy
  has_many :kyc_documents,  foreign_key: :applicant_id, inverse_of: :applicant, dependent: :destroy
  has_many :corporate_entities, class_name: "Kyc::CorporateEntity", foreign_key: :applicant_id,
           dependent: :destroy, inverse_of: :applicant
  has_many :validation_warnings, class_name: "Kyc::ValidationWarning", foreign_key: :applicant_id,
           dependent: :destroy, inverse_of: :applicant
  has_many :applicant_users, foreign_key: :applicant_id, inverse_of: :applicant
  has_many :addresses, as: :addressable, dependent: :destroy
  has_one :primary_business_address, -> { where(type: "Address::Business", primary: true) },
          class_name: "Address", as: :addressable

  validates :merchant_id, absence: true
  validates :name, presence: true
  validates :name, uniqueness: { scope: :type, case_sensitive: false }
  validates :contact_email,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    allow_blank: true

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected" }, default: "pending"

  def to_param
    id
  end
end
