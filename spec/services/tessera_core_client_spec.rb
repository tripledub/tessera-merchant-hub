# frozen_string_literal: true

require "rails_helper"

RSpec.describe TesseraCoreClient do
  let(:base_url) { "https://core.example.com" }
  let(:api_key) { "secret-key-abc" }
  let(:client) { described_class.new(base_url: base_url, api_key: api_key) }
  let(:integration_account_id) { "intacct_shop_1" }

  describe "#post_refund" do
    let(:payment_id) { "pay_123" }
    let(:url) { "#{base_url}/v1/payments/#{payment_id}/refunds" }
    let(:response_body) { { "id" => "ref_1", "status" => "pending" } }

    before do
      stub_request(:post, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "returns the parsed JSON body" do
      result = client.post_refund(shop_id: "shop_1", payment_id: payment_id, amount: 500, currency: "GBP")
      expect(result).to eq(response_body)
    end
  end

  describe "#create_integration_account" do
    let(:url) { "#{base_url}/internal/integration_accounts" }
    let(:response_body) do
      {
        "id" => integration_account_id,
        "merchant_hub_merchant_id" => "merch_1",
        "merchant_hub_shop_id" => "shop_1",
        "acquirer_key" => "sandbox"
      }
    end

    it "posts to the internal integration account endpoint" do
      stub = stub_request(:post, url)
        .with(
          headers: { "X-Internal-Api-Key" => api_key },
          body: hash_including(
            "merchant_hub_merchant_id" => "merch_1",
            "merchant_hub_shop_id" => "shop_1",
            "secret_key" => "sk_test"
          )
        )
        .to_return(status: 201, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.create_integration_account(
        merchant_hub_merchant_id: "merch_1",
        merchant_hub_shop_id: "shop_1",
        secret_key: "sk_test"
      )

      expect(result).to eq(response_body)
      expect(stub).to have_been_requested
    end

    it "does not call legacy merchant or shop CRUD paths" do
      stub_request(:post, url)
        .to_return(status: 201, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      client.create_integration_account(
        merchant_hub_merchant_id: "merch_1",
        merchant_hub_shop_id: "shop_1",
        secret_key: "sk_test"
      )

      expect(a_request(:post, %r{/v1/merchants})).not_to have_been_made
      expect(a_request(:post, %r{/v1/shops})).not_to have_been_made
    end
  end

  describe "#create_credential" do
    let(:url) { "#{base_url}/internal/integration_accounts/#{integration_account_id}/credentials" }
    let(:response_body) do
      {
        "id" => "cred_1",
        "api_key" => "pk_live_1",
        "secret_key" => "sk_live_secret",
        "signing_secret" => "whsec_abc"
      }
    end

    it "posts to the internal credentials endpoint and normalizes legacy pk/sk keys" do
      stub = stub_request(:post, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(status: 201, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.create_credential(integration_account_id: integration_account_id)

      expect(result["pk"]).to eq("pk_live_1")
      expect(result["sk"]).to eq("sk_live_secret")
      expect(result["signing_secret"]).to eq("whsec_abc")
      expect(stub).to have_been_requested
      expect(a_request(:post, %r{/v1/shops/.+/credentials})).not_to have_been_made
    end
  end

  describe "#list_credentials" do
    let(:url) { "#{base_url}/internal/integration_accounts/#{integration_account_id}/credentials" }
    let(:response_body) do
      {
        "credentials" => [
          {
            "id" => "cred_1",
            "api_key" => "pk_live_1",
            "status" => "active",
            "created_at" => "2026-01-01T00:00:00Z",
            "last_used_at" => nil,
            "ip_allowlist" => [],
            "signing_required" => false
          }
        ]
      }
    end

    it "returns normalized credential metadata without secrets" do
      stub_request(:get, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.list_credentials(integration_account_id: integration_account_id)

      expect(result.first["pk"]).to eq("pk_live_1")
      expect(result.first["created"]).to eq("2026-01-01T00:00:00Z")
      expect(result.first).not_to have_key("secret_key")
      expect(a_request(:get, %r{/v1/shops/.+/credentials})).not_to have_been_made
    end
  end

  describe "#revoke_credential" do
    let(:url) { "#{base_url}/internal/integration_accounts/#{integration_account_id}/credentials/cred_1" }

    it "deletes via the internal credentials endpoint" do
      stub = stub_request(:delete, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(
          status: 200,
          body: { "id" => "cred_1", "api_key" => "pk_live_1", "status" => "revoked" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.revoke_credential(integration_account_id: integration_account_id, credential_id: "cred_1")
      expect(result["pk"]).to eq("pk_live_1")
      expect(result["status"]).to eq("revoked")
      expect(stub).to have_been_requested
    end
  end

  describe "#configure_credential" do
    let(:url) { "#{base_url}/internal/integration_accounts/#{integration_account_id}/credentials/cred_1" }

    it "patches via the internal credentials endpoint" do
      stub = stub_request(:patch, url)
        .with(
          headers: { "X-Internal-Api-Key" => api_key },
          body: { ip_allowlist: [ "1.2.3.4" ], signing_required: true }
        )
        .to_return(
          status: 200,
          body: { "id" => "cred_1", "api_key" => "pk_live_1", "ip_allowlist" => [ "1.2.3.4" ], "signing_required" => true }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.configure_credential(
        integration_account_id: integration_account_id,
        credential_id: "cred_1",
        ip_allowlist: [ "1.2.3.4" ],
        signing_required: true
      )

      expect(result["pk"]).to eq("pk_live_1")
      expect(stub).to have_been_requested
    end
  end
end
