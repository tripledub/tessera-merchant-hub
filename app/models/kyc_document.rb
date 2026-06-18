# frozen_string_literal: true

class KycDocument < ApplicationRecord
  belongs_to :applicant,     foreign_key: :applicant_id,     inverse_of: :kyc_documents
  belongs_to :kyc_principal, foreign_key: :kyc_principal_id, inverse_of: :kyc_documents, optional: true

  has_one_attached :file

  enum :status, { pending: 0, processing: 1, complete: 2, error: 3 }, default: :pending

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
