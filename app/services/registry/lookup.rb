# frozen_string_literal: true

module Registry
  class Lookup
    Result = Data.define(:success, :registry_profile, :error_type, :error_message) do
      def self.success(registry_profile)
        new(success: true, registry_profile: registry_profile, error_type: nil, error_message: nil)
      end

      def self.failure(error_type, error_message = nil)
        new(success: false, registry_profile: nil, error_type: error_type, error_message: error_message)
      end
    end

    CLIENTS = {
      "gb" => Registry::CompaniesHouseUkClient
    }.freeze

    def self.call(applicant:)
      new(applicant: applicant).call
    end

    def initialize(applicant:)
      @applicant = applicant
    end

    def call
      client_class = CLIENTS[@applicant.registry_jurisdiction]
      return Result.failure(:not_supported) unless client_class
      return Result.failure(:invalid_number) if @applicant.company_number.blank?

      fetch_result = client_class.new.fetch(company_number: @applicant.company_number)

      if fetch_result.success
        Result.success(persist(fetch_result))
      else
        Result.failure(fetch_result.error_type, fetch_result.error_message)
      end
    end

    private

    def persist(fetch_result)
      ActiveRecord::Base.transaction do
        profile = @applicant.registry_profiles.create!(
          jurisdiction: @applicant.registry_jurisdiction,
          company_number: @applicant.company_number,
          company_name: fetch_result.company_name,
          status: fetch_result.status,
          incorporated_on: fetch_result.incorporated_on,
          fetched_at: Time.current
        )

        fetch_result.directors.each { |director| profile.directors.create!(director) }
        fetch_result.addresses.each { |address| profile.addresses.create!(address) }

        profile
      end
    end
  end
end
