# frozen_string_literal: true

require "rails_helper"

RSpec.describe ControlPlane::ShopProvisioner, type: :model do
  include TesseraInternalApiStubs

  let_it_be(:merchant) { create(:merchant) }

  describe ".create!" do
    before do
      stub_core_create_integration_account!(merchant_id: merchant.merchant_id)
    end

    it "delegates to a new instance" do
      result = described_class.create!(
        merchant_id: merchant.merchant_id,
        name: "EU Shop",
        country: "DE"
      )

      expect(result).to include("name" => "EU Shop", "country" => "DE")
      expect(result["shop_id"]).to start_with("shop_")
    end
  end

  describe "#create!" do
    let(:client) { instance_double(TesseraCoreClient) }
    let(:provisioner) { described_class.new(client: client) }

    before do
      allow(client).to receive(:create_integration_account).and_return(
        { "id" => "intacct_test_123" }
      )
    end

    it "creates a Shop record" do
      expect {
        provisioner.create!(merchant_id: merchant.merchant_id, name: "EU Shop", country: "DE")
      }.to change(Shop, :count).by(1)
    end

    it "calls the core client to create an integration account" do
      provisioner.create!(merchant_id: merchant.merchant_id, name: "EU Shop", country: "DE")

      expect(client).to have_received(:create_integration_account).with(
        merchant_hub_merchant_id: merchant.merchant_id,
        merchant_hub_shop_id: a_string_starting_with("shop_"),
        secret_key: a_string_starting_with("sk_")
      )
    end

    it "returns a hash with shop details" do
      result = provisioner.create!(
        merchant_id: merchant.merchant_id,
        name: "EU Shop",
        country: "DE",
        notification_url: "https://example.com/wh"
      )

      expect(result).to include(
        "integration_account_id" => "intacct_test_123",
        "name" => "EU Shop",
        "country" => "DE",
        "notification_url" => "https://example.com/wh"
      )
      expect(result["shop_id"]).to start_with("shop_")
    end

    it "uses a provided shop_id when given" do
      result = provisioner.create!(
        merchant_id: merchant.merchant_id,
        name: "EU Shop",
        country: "DE",
        shop_id: "shop_custom_id"
      )

      expect(result["shop_id"]).to eq("shop_custom_id")
    end

    it "persists the shop with integration_account_id from the core response" do
      result = provisioner.create!(merchant_id: merchant.merchant_id, name: "EU Shop", country: "DE")
      shop = Shop.find_by(shop_id: result["shop_id"])

      expect(shop).to be_present
      expect(shop.integration_account_id).to eq("intacct_test_123")
      expect(shop.merchant_id).to eq(merchant.merchant_id)
    end

    it "raises when the core client fails" do
      allow(client).to receive(:create_integration_account).and_raise(
        TesseraCoreClient::Error, "boom"
      )

      expect {
        provisioner.create!(merchant_id: merchant.merchant_id, name: "EU Shop", country: "DE")
      }.to raise_error(TesseraCoreClient::Error, "boom")
    end
  end
end
