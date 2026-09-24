# frozen_string_literal: true

module Kyc
  # MH-331: a staff-triggered "these two principal rows are the same person"
  # merge. survivor is the canonical row a reviewer picked (its existing
  # non-empty fields are trusted and never overwritten); loser is soft-deleted
  # by pointing merged_into at survivor rather than being destroyed, so its
  # original field values stay in the DB. Its documents are re-pointed onto
  # survivor.
  class PrincipalMergeService
    BACKFILL_FIELDS = %i[
      date_of_birth date_of_birth_month date_of_birth_year
      email address_line1 address_line2 city postcode country
    ].freeze

    Result = Data.define(:survivor, :errors) do
      def success?
        errors.empty?
      end
    end

    def self.call(survivor:, loser:)
      new(survivor: survivor, loser: loser).call
    end

    def initialize(survivor:, loser:)
      @survivor = survivor
      @loser = loser
    end

    def call
      return failure("A principal cannot be merged into itself.") if @survivor == @loser
      return failure("Principals can only be merged within the same applicant.") if @survivor.applicant_id != @loser.applicant_id
      return failure("This principal has already been merged into another one.") if @survivor.merged? || @loser.merged?

      ActiveRecord::Base.transaction do
        backfill_survivor
        @survivor.save!
        @loser.kyc_documents.update_all(kyc_principal_id: @survivor.id)
        @loser.update!(merged_into: @survivor)
      end

      Result.new(survivor: @survivor, errors: no_errors)
    end

    private

    def backfill_survivor
      BACKFILL_FIELDS.each do |field|
        next if @survivor.public_send(field).present?

        loser_value = @loser.public_send(field)
        @survivor.public_send("#{field}=", loser_value) if loser_value.present?
      end
      @survivor.role = @loser.role if @survivor.unspecified? && !@loser.unspecified?
    end

    def failure(message)
      errors = ActiveModel::Errors.new(self)
      errors.add(:base, message)
      Result.new(survivor: @survivor, errors: errors)
    end

    def no_errors
      ActiveModel::Errors.new(self)
    end
  end
end
