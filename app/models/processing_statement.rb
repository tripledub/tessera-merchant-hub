# frozen_string_literal: true

class ProcessingStatement < ApplicationRecord
  # Import now runs in ImportProcessingStatementJob, off the request/response
  # cycle, so this is a sanity cap on job runtime/memory rather than a
  # UX-driven limit — raise it if real statements routinely exceed it.
  MAX_ROWS = 50_000

  # currency is required (not just optional) — without it, every row would
  # be bucketed under a single "unknown" currency and summed together,
  # which is exactly the meaningless cross-currency blending this feature
  # exists to avoid.
  REQUIRED_FIELDS = %i[date amount currency outcome].freeze

  belongs_to :applicant
  has_one :kyc_document, dependent: :nullify, inverse_of: :processing_statement

  has_one_attached :file

  enum :status, { uploaded: 0, mapped: 1, processed: 2, error: 3 }, default: :uploaded

  validates :file, presence: true, on: :create

  def mappable?
    uploaded? || error?
  end

  def removable?
    error?
  end
end
