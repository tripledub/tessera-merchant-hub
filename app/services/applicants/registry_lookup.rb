# frozen_string_literal: true

module Applicants
  class RegistryLookup
    Result = Data.define(:success, :applicant, :error_type) do
      def self.success(applicant) = new(success: true, applicant: applicant, error_type: nil)

      def self.failure(applicant, error_type = nil) = new(success: false, applicant: applicant, error_type: error_type)
    end

    def self.call(applicant) = new(applicant).call

    def initialize(applicant)
      @applicant = applicant
    end

    def call
      result = Registry::Lookup.call(applicant: @applicant)
      record_attempt(result)
      return Result.failure(@applicant, result.error_type) unless result.success

      @applicant.update(company_name: result.registry_profile.company_name)
      Kyc::PrincipalsFromRegistry.call(result.registry_profile)
      Kyc::OwnershipFromRegistry.call(result.registry_profile)

      Result.success(@applicant)
    end

    private

    # Recorded here (not in Registry::Lookup) so PSC-chain lookups for other companies'
    # numbers cannot overwrite the applicant's own status.
    def record_attempt(result)
      @applicant.update!(registry_lookup_attempted_at: Time.current, registry_lookup_error: result.error_type&.to_s)
    end
  end
end
