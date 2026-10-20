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

      record_registry_company_details(result.registry_profile)
      Kyc::PrincipalsFromRegistry.call(result.registry_profile)
      Kyc::OwnershipFromRegistry.call(result.registry_profile)

      Result.success(@applicant)
    end

    private

    # MH-389: through the trust-order rules, so a replaced name is kept for audit and the source is recorded.
    def record_registry_company_details(profile)
      provider = Registry::Lookup.provider_for(profile.jurisdiction)
      { "company_name" => profile.company_name, "company_number" => profile.company_number }.each do |field, value|
        Provenance::CompanyFields.apply!(applicant: @applicant, field: field, value: value, source: :registry,
                                         provider: provider, retrieved_at: profile.fetched_at)
      end
    end

    # Recorded here (not in Registry::Lookup) so PSC-chain lookups for other companies'
    # numbers cannot overwrite the applicant's own status.
    def record_attempt(result)
      @applicant.update!(registry_lookup_attempted_at: Time.current, registry_lookup_error: result.error_type&.to_s)
    end
  end
end
