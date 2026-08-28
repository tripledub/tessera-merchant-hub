# frozen_string_literal: true

module Applicants
  class RegistryLookup
    Result = Data.define(:success, :applicant) do
      def self.success(applicant) = new(success: true, applicant: applicant)

      def self.failure(applicant) = new(success: false, applicant: applicant)
    end

    def self.call(applicant) = new(applicant).call

    def initialize(applicant)
      @applicant = applicant
    end

    def call
      result = Registry::Lookup.call(applicant: @applicant)
      return Result.failure(@applicant) unless result.success

      @applicant.update(company_name: result.registry_profile.company_name)
      Kyc::PrincipalsFromRegistry.call(result.registry_profile)
      Kyc::OwnershipFromRegistry.call(result.registry_profile)

      Result.success(@applicant)
    end
  end
end
