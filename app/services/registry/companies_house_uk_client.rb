# frozen_string_literal: true

require "faraday"
require "json"

module Registry
  class CompaniesHouseUkClient < Client
    def initialize(
      base_url: ENV.fetch("COMPANIES_HOUSE_URL", "https://api.company-information.service.gov.uk"),
      api_key: ENV.fetch("COMPANIES_HOUSE_API_KEY")
    )
      @connection = Faraday.new(url: base_url) do |f|
        f.request :authorization, :basic, api_key, ""
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end

    def fetch(company_number:)
      company = get("/company/#{company_number}")
      officers = get("/company/#{company_number}/officers")

      FetchResult.success(
        company_name: company["company_name"],
        status: company["company_status"],
        incorporated_on: parse_date(company["date_of_creation"]),
        directors: map_directors(officers["items"]),
        addresses: map_addresses(company["registered_office_address"])
      )
    rescue Faraday::ResourceNotFound
      FetchResult.failure(error_type: :not_found)
    rescue Faraday::UnauthorizedError
      FetchResult.failure(error_type: :unauthorized)
    rescue Faraday::TooManyRequestsError
      FetchResult.failure(error_type: :rate_limited)
    rescue Faraday::ServerError, Faraday::Error
      FetchResult.failure(error_type: :unavailable)
    end

    private

    def get(path)
      JSON.parse(@connection.get(path).body)
    end

    def parse_date(value)
      value.present? ? Date.parse(value) : nil
    end

    def map_directors(items)
      Array(items).map do |item|
        {
          name: item["name"],
          role: item["officer_role"],
          appointed_on: parse_date(item["appointed_on"]),
          resigned_on: parse_date(item["resigned_on"])
        }
      end
    end

    def map_addresses(address)
      return [] if address.blank?

      [ {
        kind: "registered",
        line1: address["address_line_1"],
        city: address["locality"],
        postcode: address["postal_code"],
        country: address["country"]
      } ]
    end
  end
end
