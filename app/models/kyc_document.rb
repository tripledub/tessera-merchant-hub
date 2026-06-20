# frozen_string_literal: true

class KycDocument < ApplicationRecord
  belongs_to :applicant,     foreign_key: :applicant_id,     inverse_of: :kyc_documents
  belongs_to :kyc_principal, foreign_key: :kyc_principal_id, inverse_of: :kyc_documents, optional: true

  has_one_attached :file

  enum :status, { pending: 0, processing: 1, complete: 2, error: 3 }, default: :pending

  enum :document_type, {
    # Identity
    passport: 0,
    driving_licence: 1,
    # Proof of address
    utility_bill: 10,
    # Corporate formation
    certificate_of_incorporation: 20,
    memorandum_of_association: 21,
    articles_of_association: 22,
    certificate_of_amendment: 23,
    # Corporate registry
    certificate_of_directors: 30,
    certificate_of_shareholders: 31,
    share_certificate: 32,
    register_of_members: 33,
    certificate_of_incumbency: 34,
    group_structure_chart: 35,
    # Corporate address
    certificate_of_registered_address: 40,
    # Financial
    bank_account_statement: 50,
    transaction_extract: 51,
    funds_flow_diagram: 52,
    business_plan: 53,
    apm_summary: 54,
    # Legal
    legal_opinion: 60,
    declaration_of_trust: 61,
    payment_agreement: 62,
    # Compliance / AML
    aml_ctf_policy: 70,
    aml_kyc_requirements: 71,
    source_of_wealth_questionnaire: 72,
    aml_ctf_questionnaire: 73
  }

  enum :classification_status, {
    unclassified: 0,
    auto_classified: 1,
    ai_suggested: 2,
    confirmed: 3,
    rejected: 4
  }, default: :unclassified, prefix: :classification

  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg image/png image/webp image/gif
    application/pdf
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-excel
    text/csv
  ].freeze

  validates :file, presence: true, on: :create
  validate :file_content_type_allowed, if: -> { file.attached? }

  private

  def file_content_type_allowed
    return if ALLOWED_CONTENT_TYPES.include?(file.content_type)

    errors.add(:file, "has an unsupported type (#{file.content_type}). Please upload an image, PDF, Excel, or CSV file.")
  end
end
