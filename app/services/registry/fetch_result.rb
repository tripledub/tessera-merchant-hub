# frozen_string_literal: true

module Registry
  FetchResult = Data.define(
    :success, :error_type, :error_message,
    :company_name, :status, :incorporated_on,
    :directors, :addresses, :people_with_significant_control
  ) do
    def self.success(company_name:, status:, incorporated_on:, directors:, addresses:, people_with_significant_control: [])
      new(
        success: true, error_type: nil, error_message: nil,
        company_name: company_name, status: status, incorporated_on: incorporated_on,
        directors: directors, addresses: addresses,
        people_with_significant_control: people_with_significant_control
      )
    end

    def self.failure(error_type:, error_message: nil)
      new(
        success: false, error_type: error_type, error_message: error_message,
        company_name: nil, status: nil, incorporated_on: nil,
        directors: [], addresses: [], people_with_significant_control: []
      )
    end
  end
end
