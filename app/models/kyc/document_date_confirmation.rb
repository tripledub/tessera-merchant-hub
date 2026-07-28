# frozen_string_literal: true

module Kyc
  # Append-only audit log of staff confirming or correcting an extracted
  # document validity date (MH-196). Every confirm/correct action creates a
  # NEW row rather than updating an existing one, so later corrections never
  # erase earlier audit events.
  #
  # `date_role` matches the abstract role keys used by
  # KycDocument#validity_dates (e.g. "expiry", "issued").
  class DocumentDateConfirmation < ApplicationRecord
    self.table_name = "kyc_document_date_confirmations"

    belongs_to :kyc_document
    belongs_to :confirmed_by, class_name: "User"

    validates :date_role, presence: true
    validates :confirmed_value, presence: true
    validates :reason, presence: true, if: :value_changed_from_extracted?
    validate :date_role_must_be_extractable_for_document, if: -> { kyc_document.present? && date_role.present? }

    # The current authoritative confirmation for a document + date role is
    # the most recently created row. Ordering by created_at with id as a
    # tiebreak guards against two confirmations landing in the same request
    # with identical (or coarse) timestamp resolution — ids are UUIDs so
    # they're not naturally sequential, but combined with created_at this is
    # enough to make the ordering deterministic without adding a dedicated
    # sequence column.
    def self.current_for(kyc_document, date_role)
      where(kyc_document: kyc_document, date_role: date_role)
        .order(created_at: :desc, id: :desc)
        .first
    end

    private

    # A reason is required only when the confirmed value contradicts a date
    # that was actually extracted. When nothing was extracted at all (a
    # missing date being entered for the first time), there is no prior
    # value to justify a discrepancy against, so no reason is required.
    def value_changed_from_extracted?
      extracted_value.present? && confirmed_value.to_s != extracted_value.to_s
    end

    # A confirmation may only target a date role that MH-195's
    # Kyc::DocumentValidity::DateExtractor actually populated for this
    # specific document, i.e. a key of KycDocument#validity_dates. That hash
    # is keyed by every role the document's resolved validity policy
    # requires, whether or not extraction found a value for it (a role with
    # nothing extracted is still present with a nil "normalized" value) — so
    # checking key membership, not value presence, is exactly "is this a role
    # that applies to this document".
    #
    # When validity_dates is empty (a document type with no resolvable/
    # enabled validity policy — inert per MH-195), NO date_role can ever
    # match, so every confirmation attempt is rejected. This is deliberate:
    # an inert document has no policy-driven notion of "expiry" or "issued"
    # at all, so there is nothing legitimate for staff to confirm or correct
    # against, and allowing an arbitrary role through would recreate the same
    # unconstrained, append-only-table-polluting hole this validation exists
    # to close.
    def date_role_must_be_extractable_for_document
      return if kyc_document.validity_dates.key?(date_role)

      errors.add(:date_role, "is not a date role extracted for this document")
    end
  end
end
