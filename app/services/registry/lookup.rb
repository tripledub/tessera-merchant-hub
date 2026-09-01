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

    def self.call(applicant:, company_number: applicant.company_number, jurisdiction: applicant.registry_jurisdiction)
      new(applicant: applicant, company_number: company_number, jurisdiction: jurisdiction).call
    end

    def initialize(applicant:, company_number: applicant.company_number, jurisdiction: applicant.registry_jurisdiction)
      @applicant = applicant
      @company_number = company_number
      @jurisdiction = jurisdiction
    end

    def call
      client_class = CLIENTS[@jurisdiction]
      return Result.failure(:not_supported) unless client_class
      return Result.failure(:invalid_number) if @company_number.blank?

      fetch_result = client_class.new.fetch(company_number: @company_number)

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
          jurisdiction: @jurisdiction,
          company_number: @company_number,
          company_name: fetch_result.company_name,
          status: fetch_result.status,
          incorporated_on: fetch_result.incorporated_on,
          fetched_at: Time.current,
          raw_response: fetch_result.raw_response
        )

        fetch_result.directors.each { |director| profile.directors.create!(director) }
        fetch_result.addresses.each { |address| profile.addresses.create!(address) }
        fetch_result.people_with_significant_control.each { |psc| profile.people_with_significant_control.create!(psc) }

        profile
      end
    end
  end
end
