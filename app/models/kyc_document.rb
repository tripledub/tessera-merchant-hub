# frozen_string_literal: true

class KycDocument < ApplicationRecord
  belongs_to :applicant,     foreign_key: :applicant_id,     inverse_of: :kyc_documents
  belongs_to :kyc_principal, foreign_key: :kyc_principal_id, inverse_of: :kyc_documents, optional: true
  belongs_to :corporate_entity, class_name: "Kyc::CorporateEntity", optional: true
  belongs_to :superseded_by_kyc_document, class_name: "KycDocument", optional: true
  belongs_to :processing_statement, optional: true, inverse_of: :kyc_document

  include Commentable

  has_many :corporate_entities, class_name: "Kyc::CorporateEntity", foreign_key: :kyc_document_id,
           dependent: :destroy, inverse_of: :kyc_document
  has_many :validation_warnings, class_name: "Kyc::ValidationWarning", foreign_key: :kyc_document_id,
           dependent: :destroy, inverse_of: :kyc_document
  has_many :date_confirmations, class_name: "Kyc::DocumentDateConfirmation", foreign_key: :kyc_document_id,
           dependent: :destroy, inverse_of: :kyc_document
  has_many :validity_assessments, class_name: "Kyc::DocumentValidityAssessment", foreign_key: :kyc_document_id,
           dependent: :destroy, inverse_of: :kyc_document
  has_one :replacement_requirement, class_name: "Kyc::DocumentReplacementRequirement",
          foreign_key: :kyc_document_id, dependent: :destroy, inverse_of: :kyc_document

  has_one_attached :file

  # MH-199: excludes documents that have been replaced by a newer upload of
  # the same type (see Kyc::DocumentExpiryMonitoringJob). Used anywhere a
  # "currently active" set of documents is needed for readiness/completeness,
  # so a superseded, possibly-expired document doesn't count against (or
  # for) an applicant once a valid replacement is on file.
  scope :not_superseded, -> { where(superseded_by_kyc_document_id: nil) }

  # Surfaces documents needing attention first: processing, then pending,
  # then errored, with complete documents last.
  scope :ordered_by_review_priority, -> {
    order(Arel.sql("CASE status WHEN 1 THEN 0 WHEN 0 THEN 1 WHEN 3 THEN 2 WHEN 2 THEN 3 END"), :created_at)
  }

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
    processing_statement: 55,
    # Legal
    legal_opinion: 60,
    declaration_of_trust: 61,
    payment_agreement: 62,
    # Compliance / AML
    aml_ctf_policy: 70,
    aml_kyc_requirements: 71,
    source_of_wealth_questionnaire: 72,
    aml_ctf_questionnaire: 73,
    vasp_registration: 74,
    wallet_custody_infrastructure_attestation: 75,
    # Content type the AI classifier can't process at all (e.g. xlsx/xls —
    # see DocumentClassifiers::AiFallback::SUPPORTED_CONTENT_TYPES). Acknowledged
    # and kept on file, but never auto-extracted; a human can reclassify it later.
    other: 99
  }

  ROUTING_ONLY_DOCUMENT_TYPES = %w[processing_statement].freeze

  def self.manually_selectable_document_types
    document_types.keys - ROUTING_ONLY_DOCUMENT_TYPES
  end

  enum :classification_status, {
    unclassified: 0,
    auto_classified: 1,
    ai_suggested: 2,
    confirmed: 3,
    rejected: 4
  }, default: :unclassified, prefix: :classification

  # Nullable, no default — nil means no flag has ever been set, distinct
  # from `status` above which tracks classification/extraction progress.
  enum :comment_status, { requires_follow_up: 0, resolved: 1 }, prefix: :comment

  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg image/png image/webp image/gif
    application/pdf
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-excel
    text/csv
  ].freeze
  MAX_FILE_SIZE = 10.megabytes

  # document_type is nil until classification completes (or if it errors),
  # so any UI/report grouping documents by type must label that case
  # explicitly rather than calling #humanize on nil (MH-271).
  def self.document_type_label(type)
    return I18n.t("kyc.documents.classification.status.unclassified") if type.nil?

    I18n.t("kyc.documents.document_types.#{type}", default: type.humanize)
  end

  def extraction_schema
    ExtractionData::Base.for(document_type)
  end

  def typed_extracted_data
    return nil if extracted_data.blank? || document_type.blank?

    extraction_schema.new(extracted_data)
  end

  validates :file, presence: true, on: :create
  validate :file_content_type_allowed, if: -> { file.attached? }
  validate :file_size_allowed, if: -> { file.attached? }

  def needs_review?
    classification_ai_suggested? || classification_unclassified?
  end

  private

  def file_content_type_allowed
    return if ALLOWED_CONTENT_TYPES.include?(file.content_type)

    errors.add(:file, "has an unsupported type (#{file.content_type}). Please upload an image, PDF, Excel, or CSV file.")
  end

  def file_size_allowed
    return if file.blob.byte_size <= MAX_FILE_SIZE

    errors.add(:file, "must be less than 10 MB")
  end
end
