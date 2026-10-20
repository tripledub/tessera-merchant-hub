# frozen_string_literal: true

module Provenance
  # MH-389: re-runs the registry lookup and records differences from what we hold as
  # conflicts. Unlike a staff-triggered lookup it never overwrites the applicant's data.
  class RegistryRecheck
    def self.call(applicant) = new(applicant).call

    def initialize(applicant)
      @applicant = applicant
    end

    # Returns :skipped, :failed or :checked.
    def call
      return :skipped unless checkable?

      result = Registry::Lookup.call(applicant: @applicant)
      record_attempt(result)
      return :failed unless result.success

      flag_name_difference(result.registry_profile)
      :checked
    end

    private

    def checkable?
      @applicant.company_number.present? && Registry::Lookup.client_class_for(@applicant.registry_jurisdiction).present?
    end

    def flag_name_difference(profile)
      CompanyFields.flag_difference!(
        applicant: @applicant, field: "company_name", registry_value: profile.company_name,
        provider: Registry::Lookup.provider_for(profile.jurisdiction)
      )
    end

    def record_attempt(result)
      @applicant.update!(registry_lookup_attempted_at: Time.current, registry_lookup_error: result.error_type&.to_s)
    end
  end
end
