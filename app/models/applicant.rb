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
  enum :registry_jurisdiction, { gb: "gb", mt: "mt", cy: "cy" }, validate: { allow_nil: true }

  def to_param
    id
  end

  # MH-198: the stable reference date document-validity freshness checks are
  # assessed against. Completeness/readiness are recomputed on every
  # request, so they must NOT pass Date.current straight through to
  # Kyc::DocumentValidity::Assessor — a freshness document (e.g.
  # utility_bill) that was acceptable when submitted would otherwise
  # silently flip to "stale" purely because time passed while the
  # application sat in a queue, with nothing about the document itself
  # changing. There is no dedicated "compliance review" or "review period"
  # model in this codebase (only this single, ongoing Applicant/
  # OnboardingSession concept), so `created_at` — when this KYC application
  # began — is the most stable anchor available today. It is a core,
  # always-present AR timestamp (unlike OnboardingSession, which is
  # optional/destroyable), and it stays fixed for the life of the
  # applicant, which is exactly what "assess freshness against a stable
  # application/review start date" (MH-198 AC) requires. If a distinct
  # "compliance review" concept is ever introduced, this is the method to
  # repoint.
  def validity_reference_date
    created_at.to_date
  end
end
