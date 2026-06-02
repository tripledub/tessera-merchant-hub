# frozen_string_literal: true

require "rails_helper"

RSpec.describe TesseraCoreClient do
  let(:base_url) { "https://core.example.com" }
  let(:api_key) { "secret-key-abc" }
  let(:client) { described_class.new(base_url: base_url, api_key: api_key) }
  let(:headers) { { "X-Internal-Api-Key" => api_key, "Content-Type" => "application/json" } }

  describe "#post_refund" do
    let(:payment_id) { "pay_123" }
    let(:url) { "#{base_url}/v1/payments/#{payment_id}/refunds" }
    let(:request_body) { { shop_id: "shop_1", amount: 500, currency: "GBP" } }
    let(:response_body) { { "id" => "ref_1", "status" => "pending" } }

    context "when the request succeeds (200)" do
      before do
        stub_request(:post, url)
          .with(
            headers: { "X-Internal-Api-Key" => api_key },
            body: hash_including("shop_id" => "shop_1")
          )
          .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns the parsed JSON body" do
        result = client.post_refund(shop_id: "shop_1", payment_id: payment_id, amount: 500, currency: "GBP")
        expect(result).to eq(response_body)
      end
    end

    context "when the server responds 404" do
      before do
        stub_request(:post, url).to_return(status: 404, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "raises NotFoundError" do
        expect {
          client.post_refund(shop_id: "shop_1", payment_id: payment_id, amount: 500, currency: "GBP")
        }.to raise_error(TesseraCoreClient::NotFoundError)
      end
    end

    context "when the server responds 401" do
      before do
        stub_request(:post, url).to_return(status: 401, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "raises UnauthorizedError" do
        expect {
          client.post_refund(shop_id: "shop_1", payment_id: payment_id, amount: 500, currency: "GBP")
        }.to raise_error(TesseraCoreClient::UnauthorizedError)
      end
    end

    context "when the server responds 422" do
      before do
        stub_request(:post, url).to_return(status: 422, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "raises RefundError" do
        expect {
          client.post_refund(shop_id: "shop_1", payment_id: payment_id, amount: 500, currency: "GBP")
        }.to raise_error(TesseraCoreClient::RefundError)
      end
    end

    context "when the server responds 500" do
      before do
        stub_request(:post, url).to_return(status: 500, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "raises ServerError" do
        expect {
          client.post_refund(shop_id: "shop_1", payment_id: payment_id, amount: 500, currency: "GBP")
        }.to raise_error(TesseraCoreClient::ServerError)
      end
    end

    it "sends the X-Internal-Api-Key header" do
      stub = stub_request(:post, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      client.post_refund(shop_id: "shop_1", payment_id: payment_id, amount: 500, currency: "GBP")
      expect(stub).to have_been_requested
    end
  end

  describe "#post_void" do
    let(:payment_id) { "pay_456" }
    let(:url) { "#{base_url}/v1/payments/#{payment_id}/void" }
    let(:response_body) { { "id" => payment_id, "status" => "voided" } }

    context "when the request succeeds (200)" do
      before do
        stub_request(:post, url)
          .with(headers: { "X-Internal-Api-Key" => api_key })
          .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns the parsed JSON body" do
        result = client.post_void(shop_id: "shop_1", payment_id: payment_id)
        expect(result).to eq(response_body)
      end
    end

    context "when the server responds 404" do
      before do
        stub_request(:post, url).to_return(status: 404, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "raises NotFoundError" do
        expect { client.post_void(shop_id: "shop_1", payment_id: payment_id) }
          .to raise_error(TesseraCoreClient::NotFoundError)
      end
    end

    context "when the server responds 401" do
      before do
        stub_request(:post, url).to_return(status: 401, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "raises UnauthorizedError" do
        expect { client.post_void(shop_id: "shop_1", payment_id: payment_id) }
          .to raise_error(TesseraCoreClient::UnauthorizedError)
      end
    end

    context "when the server responds 500" do
      before do
        stub_request(:post, url).to_return(status: 500, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "raises ServerError" do
        expect { client.post_void(shop_id: "shop_1", payment_id: payment_id) }
          .to raise_error(TesseraCoreClient::ServerError)
      end
    end

    it "sends the X-Internal-Api-Key header" do
      stub = stub_request(:post, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      client.post_void(shop_id: "shop_1", payment_id: payment_id)
      expect(stub).to have_been_requested
    end
  end

  describe "#create_merchant" do
    let(:url) { "#{base_url}/v1/merchants" }
    let(:response_body) { { "merchant_id" => "mer_1", "name" => "Acme" } }

    it "posts the merchant payload and returns parsed JSON" do
      stub = stub_request(:post, url)
        .with(
          headers: { "X-Internal-Api-Key" => api_key },
          body: { name: "Acme", company_name: "Acme Ltd", country: "GB" }
        )
        .to_return(status: 201, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.create_merchant(name: "Acme", company_name: "Acme Ltd", country: "GB")
      expect(result).to eq(response_body)
      expect(stub).to have_been_requested
    end

    it "omits nil optional attributes" do
      stub = stub_request(:post, url)
        .with(body: { name: "Acme" })
        .to_return(status: 201, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      client.create_merchant(name: "Acme")
      expect(stub).to have_been_requested
    end

    it "raises UnauthorizedError on 401" do
      stub_request(:post, url).to_return(status: 401, body: "{}")
      expect { client.create_merchant(name: "Acme") }
        .to raise_error(TesseraCoreClient::UnauthorizedError)
    end
  end

  describe "#create_shop" do
    let(:merchant_id) { "mer_1" }
    let(:url) { "#{base_url}/v1/merchants/#{merchant_id}/shops" }
    let(:response_body) { { "shop_id" => "shop_1", "name" => "Main" } }

    it "posts the shop payload and returns parsed JSON" do
      stub = stub_request(:post, url)
        .with(
          headers: { "X-Internal-Api-Key" => api_key },
          body: { name: "Main", country: "GB", notification_url: "https://x.test/hook" }
        )
        .to_return(status: 201, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.create_shop(
        merchant_id: merchant_id, name: "Main", country: "GB", notification_url: "https://x.test/hook"
      )
      expect(result).to eq(response_body)
      expect(stub).to have_been_requested
    end

    it "raises NotFoundError on 404" do
      stub_request(:post, url).to_return(status: 404, body: "{}")
      expect { client.create_shop(merchant_id: merchant_id, name: "Main", country: "GB") }
        .to raise_error(TesseraCoreClient::NotFoundError)
    end
  end

  describe "#update_shop" do
    let(:shop_id) { "shop_1" }
    let(:url) { "#{base_url}/v1/shops/#{shop_id}" }
    let(:response_body) { { "shop_id" => shop_id, "name" => "Renamed" } }

    it "patches the shop attributes and returns parsed JSON" do
      stub = stub_request(:patch, url)
        .with(
          headers: { "X-Internal-Api-Key" => api_key },
          body: { name: "Renamed", notification_url: "https://x.test/hook2" }
        )
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.update_shop(shop_id: shop_id, name: "Renamed", notification_url: "https://x.test/hook2")
      expect(result).to eq(response_body)
      expect(stub).to have_been_requested
    end

    it "raises ServerError on 500" do
      stub_request(:patch, url).to_return(status: 500, body: "{}")
      expect { client.update_shop(shop_id: shop_id, name: "Renamed") }
        .to raise_error(TesseraCoreClient::ServerError)
    end
  end

  describe "#create_credential" do
    let(:shop_id) { "shop_1" }
    let(:url) { "#{base_url}/v1/shops/#{shop_id}/credentials" }
    let(:response_body) do
      { "pk" => "pk_live_1", "sk" => "sk_live_secret", "signing_secret" => "whsec_abc" }
    end

    it "posts to the credentials endpoint and exposes the plaintext secrets" do
      stub = stub_request(:post, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(status: 201, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.create_credential(shop_id: shop_id)
      expect(result).to eq(response_body)
      expect(result["sk"]).to eq("sk_live_secret")
      expect(result["signing_secret"]).to eq("whsec_abc")
      expect(stub).to have_been_requested
    end

    it "raises NotFoundError on 404" do
      stub_request(:post, url).to_return(status: 404, body: "{}")
      expect { client.create_credential(shop_id: shop_id) }
        .to raise_error(TesseraCoreClient::NotFoundError)
    end
  end

  describe "#list_credentials" do
    let(:shop_id) { "shop_1" }
    let(:url) { "#{base_url}/v1/shops/#{shop_id}/credentials" }
    let(:response_body) do
      [
        {
          "pk" => "pk_live_1", "status" => "active", "created" => "2026-01-01T00:00:00Z",
          "last_used" => nil, "ip_allowlist" => [], "signing_required" => false
        }
      ]
    end

    it "gets the credentials and returns metadata without secrets" do
      stub = stub_request(:get, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.list_credentials(shop_id: shop_id)
      expect(result).to eq(response_body)
      expect(result.first).not_to have_key("sk")
      expect(stub).to have_been_requested
    end

    it "raises UnauthorizedError on 401" do
      stub_request(:get, url).to_return(status: 401, body: "{}")
      expect { client.list_credentials(shop_id: shop_id) }
        .to raise_error(TesseraCoreClient::UnauthorizedError)
    end
  end

  describe "#revoke_credential" do
    let(:shop_id) { "shop_1" }
    let(:id) { "cred_1" }
    let(:url) { "#{base_url}/v1/shops/#{shop_id}/credentials/#{id}" }

    it "deletes the credential and returns parsed JSON" do
      stub = stub_request(:delete, url)
        .with(headers: { "X-Internal-Api-Key" => api_key })
        .to_return(status: 200, body: { "pk" => "pk_live_1", "status" => "revoked" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = client.revoke_credential(shop_id: shop_id, id: id)
      expect(result).to eq("pk" => "pk_live_1", "status" => "revoked")
      expect(stub).to have_been_requested
    end

    it "raises NotFoundError on 404" do
      stub_request(:delete, url).to_return(status: 404, body: "{}")
      expect { client.revoke_credential(shop_id: shop_id, id: id) }
        .to raise_error(TesseraCoreClient::NotFoundError)
    end
  end

  describe "#configure_credential" do
    let(:shop_id) { "shop_1" }
    let(:id) { "cred_1" }
    let(:url) { "#{base_url}/v1/shops/#{shop_id}/credentials/#{id}" }
    let(:response_body) do
      { "pk" => "pk_live_1", "ip_allowlist" => [ "1.2.3.4" ], "signing_required" => true }
    end

    it "patches the credential config and returns parsed JSON" do
      stub = stub_request(:patch, url)
        .with(
          headers: { "X-Internal-Api-Key" => api_key },
          body: { ip_allowlist: [ "1.2.3.4" ], signing_required: true }
        )
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.configure_credential(
        shop_id: shop_id, id: id, ip_allowlist: [ "1.2.3.4" ], signing_required: true
      )
      expect(result).to eq(response_body)
      expect(stub).to have_been_requested
    end

    it "omits nil attributes from the payload" do
      stub = stub_request(:patch, url)
        .with(body: { signing_required: false })
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      client.configure_credential(shop_id: shop_id, id: id, signing_required: false)
      expect(stub).to have_been_requested
    end

    it "raises NotFoundError on 404" do
      stub_request(:patch, url).to_return(status: 404, body: "{}")
      expect { client.configure_credential(shop_id: shop_id, id: id, signing_required: true) }
        .to raise_error(TesseraCoreClient::NotFoundError)
    end
  end
end
