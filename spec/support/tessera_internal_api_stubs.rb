# frozen_string_literal: true

module TesseraInternalApiStubs
  def stub_core_create_integration_account!(
    merchant_id:,
    shop_id: nil,
    integration_account_id: nil,
    name: "Acme EU",
    country: "DE"
  )
    stub_request(:post, %r{/internal/integration_accounts\z}).to_return do |request|
      body = JSON.parse(request.body)
      shop_id ||= body["merchant_hub_shop_id"]
      integration_account_id ||= "intacct_#{shop_id}"

      {
        status: 201,
        body: {
          id: integration_account_id,
          merchant_hub_merchant_id: merchant_id,
          merchant_hub_shop_id: shop_id,
          acquirer_key: "sandbox"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      }
    end
  end

  def stub_core_list_credentials!(integration_account_id:, response_body: [])
    stub_request(:get, %r{/internal/integration_accounts/#{integration_account_id}/credentials\z})
      .to_return(
        status: 200,
        body: { credentials: response_body }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_core_create_credential!(integration_account_id:, response_body:)
    stub_request(:post, %r{/internal/integration_accounts/#{integration_account_id}/credentials\z})
      .to_return(status: 201, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_core_revoke_credential!(integration_account_id:, credential_id:, response_body:)
    stub_request(:delete, %r{/internal/integration_accounts/#{integration_account_id}/credentials/#{credential_id}\z})
      .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
  end
end

RSpec.configure do |config|
  config.include TesseraInternalApiStubs
end
