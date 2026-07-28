# frozen_string_literal: true

module Kyc
  # Immutable historical record of a single document-validity assessment
  # (MH-197). Every call to Kyc::DocumentValidity::Assessor appends a NEW row
  # rather than updating an existing one, so reassessing a document never
  # loses the decision history behind an earlier outcome.
  #
  # `policy_version` is a denormalized snapshot of the resolved policy's
  # `version` integer at assessment time, kept alongside the
  # `kyc_document_validity_policy_id` foreign key so the policy version
  # behind every historical decision stays trivially queryable/explainable
  # even if the policy association were ever to change shape later.
  class DocumentValidityAssessment < ApplicationRecord
    self.table_name = "kyc_document_validity_assessments"

    class ImmutableError < StandardError; end

    belongs_to :kyc_document
    belongs_to :kyc_document_validity_policy, class_name: "Kyc::DocumentValidityPolicy"

    # `suffix: true` avoids the "valid" enum value colliding with
    # ActiveRecord's own `#valid?` instance method (e.g. this generates
    # `valid_outcome?` instead of `valid?`).
    enum :outcome, {
      valid: 0,
      expiring_soon: 1,
      expired: 2,
      stale: 3,
      confirmation_required: 4
    }, suffix: true

    validates :policy_version, presence: true
    validates :assessed_at, presence: true
    validates :reference_date, presence: true
    validates :outcome, presence: true
    validates :reason_code, presence: true

    before_update :raise_immutable_error

    # The current authoritative assessment for a document is the most
    # recently created row. Ordering by assessed_at with id as a tiebreak
    # mirrors Kyc::DocumentDateConfirmation.current_for so two assessments
    # landing with identical (or coarse) timestamp resolution still resolve
    # deterministically.
    def self.current_for(kyc_document)
      where(kyc_document: kyc_document)
        .order(assessed_at: :desc, id: :desc)
        .first
    end

    private

    def raise_immutable_error
      raise ImmutableError, "Kyc::DocumentValidityAssessment records are append-only and cannot be updated; " \
                             "create a new assessment instead"
    end
  end
end
