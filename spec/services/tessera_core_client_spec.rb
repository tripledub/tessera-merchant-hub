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
end
