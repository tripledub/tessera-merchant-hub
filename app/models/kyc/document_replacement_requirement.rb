# frozen_string_literal: true

module Kyc
  # MH-199: a stateful (not append-only) requirement to replace an expiring
  # document. Transitions warned -> escalated -> closed, driven by
  # Kyc::DocumentExpiryMonitoringJob. A given kyc_document has at most one
  # requirement row for its whole lifetime: once closed, the OLD document's
  # story is over; a later-approaching-expiry replacement gets its own,
  # separate row keyed to its own id (see db/migrate/..._create_kyc_document_
  # replacement_requirements.rb for the reasoning behind the plain unique
  # index on kyc_document_id).
  class DocumentReplacementRequirement < ApplicationRecord
    self.table_name = "kyc_document_replacement_requirements"

    class InvalidTransitionError < StandardError; end

    belongs_to :kyc_document
    belongs_to :superseded_by_kyc_document, class_name: "KycDocument", optional: true

    enum :status, { warned: 0, escalated: 1, closed: 2 }

    validates :kyc_document_id, uniqueness: true
    validates :opened_at, presence: true

    def self.current_for(kyc_document)
      find_by(kyc_document: kyc_document)
    end

    # Idempotent: escalating an already-escalated (or closed) requirement is
    # a no-op rather than an error, since the daily job may see the same
    # state repeatedly (retries, or a document that stays past the 30-day
    # threshold on every subsequent run).
    def escalate!(at: Time.current)
      return if escalated? || closed?

      update!(status: :escalated, escalated_at: at)
    end

    # Closing an already-closed requirement is a no-op for the same reason.
    def close!(superseded_by:, at: Time.current)
      return if closed?

      update!(status: :closed, closed_at: at, superseded_by_kyc_document: superseded_by)
    end
  end
end
