# frozen_string_literal: true

module Registry
  FetchResult = Data.define(
    :success, :error_type, :error_message,
    :company_name, :status, :incorporated_on,
    :directors, :addresses
  ) do
    def self.success(company_name:, status:, incorporated_on:, directors:, addresses:)
      new(
        success: true, error_type: nil, error_message: nil,
        company_name: company_name, status: status, incorporated_on: incorporated_on,
        directors: directors, addresses: addresses
      )
    end

    def self.failure(error_type:, error_message: nil)
      new(
        success: false, error_type: error_type, error_message: error_message,
        company_name: nil, status: nil, incorporated_on: nil,
        directors: [], addresses: []
      )
    end
  end
end
