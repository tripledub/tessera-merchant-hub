# frozen_string_literal: true

module Kyc
  # MH-303 (AC5): resolves a document's registry date-of-birth mismatch
  # (KycDocument#dob_mismatch_kyc_principal) once a reviewer has looked at it.
  #
  # link_anyway: the reviewer believes it's the same person despite the
  #   month/year disagreement (e.g. an OCR day/month swap, or a Companies
  #   House data error) — links the document, backfills the principal's full
  #   date of birth from the extraction, and confirms the principal.
  # different_person: the reviewer believes it's someone else — creates a new
  #   unconfirmed principal from the extraction (mirrors
  #   PrincipalMatcherService's own passport auto-creation) and links the
  #   document to that instead, leaving the original registry principal alone.
  #
  # Either way, an append-only Kyc::PrincipalMatchOverride audit row is
  # written first and the resolution only proceeds if it saves (a required
  # reason is the only validation today).
  class PrincipalMatchOverrideService
    Result = Data.define(:override, :errors) do
      def success?
        errors.empty?
      end
    end

    def self.call(document:, resolution:, reason:, actor:)
      new(document: document, resolution: resolution, reason: reason, actor: actor).call
    end

    def initialize(document:, resolution:, reason:, actor:)
      @document = document
      @resolution = resolution
      @reason = reason
      @actor = actor
    end

    def call
      candidate = @document.dob_mismatch_kyc_principal
      return failure("There is no date of birth mismatch to resolve on this document.") unless candidate
      return failure("is not a valid resolution") unless %w[link_anyway different_person].include?(@resolution.to_s)

      if @resolution.to_s == "link_anyway"
        link_anyway(candidate)
      else
        different_person(candidate)
      end
    end

    private

    def link_anyway(candidate)
      override = build_override(candidate, :link_anyway)
      return Result.new(override: override, errors: override.errors) unless override.save

      candidate.update!(date_of_birth: extracted_date_of_birth) if extracted_date_of_birth
      candidate.confirmed!
      @document.update!(
        kyc_principal: candidate,
        match_method: "override_linked",
        match_confidence: 1.0,
        dob_mismatch_kyc_principal: nil
      )

      Result.new(override: override, errors: override.errors)
    end

    def different_person(candidate)
      override = build_override(candidate, :different_person)
      return Result.new(override: override, errors: override.errors) unless override.save

      new_principal = @document.applicant.kyc_principals.create!(
        name: extracted_full_name,
        date_of_birth: extracted_date_of_birth,
        status: :unconfirmed,
        # MH-307: a passport alone is no evidence of role.
        role: :unspecified
      )
      @document.update!(
        kyc_principal: new_principal,
        match_method: "exact",
        match_confidence: 1.0,
        dob_mismatch_kyc_principal: nil
      )

      Result.new(override: override, errors: override.errors)
    end

    def build_override(candidate, resolution)
      Kyc::PrincipalMatchOverride.new(
        kyc_document: @document,
        kyc_principal: candidate,
        resolution: resolution,
        reason: @reason,
        resolved_by: @actor
      )
    end

    def extracted_full_name
      @document.extracted_data["full_name"]
    end

    def extracted_date_of_birth
      Date.parse(@document.extracted_data["date_of_birth"])
    rescue Date::Error, TypeError, ArgumentError
      nil
    end

    def failure(message)
      errors = ActiveModel::Errors.new(self)
      errors.add(:base, message)
      Result.new(override: nil, errors: errors)
    end
  end
end
