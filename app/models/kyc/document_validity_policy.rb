# frozen_string_literal: true

module Kyc
  class DocumentValidityPolicy < ApplicationRecord
    self.table_name = "kyc_document_validity_policies"

    class ImmutableError < StandardError; end

    IMMUTABLE_ATTRIBUTES = %w[
      document_type version effective_from mode required_dates warning_thresholds max_age_months blocking
    ].freeze

    enum :mode, { expires: 0, freshness: 1 }

    validates :document_type, presence: true
    validates :version, presence: true, uniqueness: { scope: :document_type }
    validates :effective_from, presence: true
    validates :mode, presence: true
    validates :max_age_months, presence: true, if: -> { mode == "freshness" }

    before_update :guard_immutable_attributes

    def self.publish!(document_type:, effective_from:, mode:, required_dates:, warning_thresholds: [],
                       max_age_months: nil, blocking: true, enabled: true)
      next_version = where(document_type: document_type).maximum(:version).to_i + 1

      create!(
        document_type: document_type,
        version: next_version,
        effective_from: effective_from,
        mode: mode,
        required_dates: required_dates,
        warning_thresholds: warning_thresholds,
        max_age_months: max_age_months,
        blocking: blocking,
        enabled: enabled
      )
    end

    private

    def guard_immutable_attributes
      changed_immutable = (changed & IMMUTABLE_ATTRIBUTES)
      return if changed_immutable.empty?

      raise ImmutableError, "cannot modify #{changed_immutable.join(', ')} on a published policy version " \
                             "(document_type=#{document_type}, version=#{version}); publish a new version instead"
    end
  end
end
