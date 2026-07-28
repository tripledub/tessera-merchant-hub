# frozen_string_literal: true

module Kyc
  module DocumentValidity
    # Confirms or corrects a single extracted validity date (MH-196). Looks
    # up the current extracted value for the given role from
    # KycDocument#validity_dates, snapshots it alongside the staff-supplied
    # confirmed value, and appends a new Kyc::DocumentDateConfirmation audit
    # row — it never updates an existing one.
    #
    # Deliberately out of scope: this service does NOT recompute or clear
    # KycDocument#validity_confirmation_required. That flag is owned by the
    # (not-yet-built) MH-197 assessment service, which will consult
    # confirmations directly; flipping it here would invent partial logic
    # that MH-197 would have to reconcile with.
    class DateConfirmationService
      Result = Data.define(:confirmation, :errors) do
        def success?
          errors.empty?
        end
      end

      def self.call(document:, date_role:, confirmed_value:, actor:, reason: nil)
        new(document: document, date_role: date_role, confirmed_value: confirmed_value, reason: reason,
            actor: actor).call
      end

      def initialize(document:, date_role:, confirmed_value:, actor:, reason:)
        @document = document
        @date_role = date_role
        @confirmed_value = confirmed_value
        @reason = reason
        @actor = actor
      end

      def call
        confirmation = Kyc::DocumentDateConfirmation.new(
          kyc_document: @document,
          date_role: @date_role,
          extracted_value: extracted_value,
          confirmed_value: @confirmed_value,
          reason: @reason,
          confirmed_by: @actor
        )

        confirmation.save
        Result.new(confirmation: confirmation, errors: confirmation.errors)
      end

      private

      # The current extracted value for this role, per the MH-195 shape:
      # validity_dates["expiry"]["normalized"], a normalized ISO8601 date
      # string, or nil if nothing was extracted/it failed to normalize.
      def extracted_value
        @document.validity_dates.dig(@date_role, "normalized")
      end
    end
  end
end
