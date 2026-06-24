# frozen_string_literal: true

require "rails_helper"

RSpec.describe ControlPlane::ShopConfigStore, type: :model do
  let_it_be(:merchant) { create(:merchant) }
  let_it_be(:shop)     { create(:shop, :with_merchant, merchant: merchant) }

  describe ".update!" do
    it "delegates to a new instance" do
      result = described_class.update!(shop_id: shop.shop_id, test_mode: true)

      expect(result).to include("shop_id" => shop.shop_id, "test_mode" => true)
    end
  end

  describe "#update!" do
    subject(:store) { described_class.new }

    it "updates notification_url on the shop" do
      store.update!(shop_id: shop.shop_id, notification_url: "https://new.example.com/hook")

      expect(shop.reload.notification_url).to eq("https://new.example.com/hook")
    end

    it "updates test_mode on the shop" do
      store.update!(shop_id: shop.shop_id, test_mode: true)

      expect(shop.reload.test_mode).to be true
    end

    it "updates both notification_url and test_mode" do
      store.update!(shop_id: shop.shop_id, notification_url: "https://both.example.com", test_mode: false)

      shop.reload
      expect(shop.notification_url).to eq("https://both.example.com")
      expect(shop.test_mode).to be false
    end

    it "returns a hash with shop_id and updated values" do
      result = store.update!(shop_id: shop.shop_id, notification_url: "https://x.com/wh", test_mode: true)

      expect(result).to eq(
        "shop_id" => shop.shop_id,
        "notification_url" => "https://x.com/wh",
        "test_mode" => true
      )
    end

    it "returns only shop_id when no attributes are given" do
      result = store.update!(shop_id: shop.shop_id)

      expect(result).to eq("shop_id" => shop.shop_id)
    end

    it "touches updated_at" do
      freeze_time do
        store.update!(shop_id: shop.shop_id, test_mode: true)
        expect(shop.reload.updated_at).to be_within(1.second).of(Time.current)
      end
    end
  end
end
