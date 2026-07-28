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
  end
end
