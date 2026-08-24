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

        create_principal(name: director.name, role: role)
      end
    end

    private

    def role_for(director)
      return :director if director.role&.include?("director")

      :secretary if director.role&.include?("secretary")
    end

    def create_principal(name:, role:)
      return if @applicant.kyc_principals.where("LOWER(name) = ?", name.downcase).exists?

      @applicant.kyc_principals.create!(name: name, role: role, source: :registry_fetched)
    end
  end
end
