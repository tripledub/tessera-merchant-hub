# frozen_string_literal: true

module Kyc
  class PrincipalsFromRegistry
    def self.call(registry_profile)
      new(registry_profile).call
    end

    def initialize(registry_profile)
      @registry_profile = registry_profile
      @applicant = registry_profile.applicant
    end

    def call
      @registry_profile.directors.where(resigned_on: nil).find_each do |director|
        role = role_for(director)
        next unless role

        create_principal(
          name: director.name,
          role: role,
          date_of_birth_month: director.date_of_birth_month,
          date_of_birth_year: director.date_of_birth_year
        )
      end
    end

    private

    def role_for(director)
      return :director if director.role&.include?("director")

      :secretary if director.role&.include?("secretary")
    end

    def create_principal(name:, role:, date_of_birth_month:, date_of_birth_year:)
      existing = @applicant.kyc_principals.active.where("LOWER(name) = ?", name.downcase).first
      principal = existing || @applicant.kyc_principals.create!(
        name: name,
        role: role,
        source: :registry_fetched,
        date_of_birth_month: date_of_birth_month,
        date_of_birth_year: date_of_birth_year
      )
      record_provenance(principal)
    end

    # MH-389: a registry match corroborates a declared principal without creating a duplicate.
    def record_provenance(principal)
      Provenance::Records.record!(
        applicant: @applicant, record: principal, source: :registry,
        provider: Registry::Lookup.provider_for(@registry_profile.jurisdiction),
        retrieved_at: @registry_profile.fetched_at
      )
    end
  end
end
