# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shops::UpdateSettings do
  let(:shop) { create(:shop, notification_url: nil, test_mode: false, display_name: nil) }

  describe ".call" do
    it "updates display_name, notification_url, and test_mode" do
      result = described_class.call(shop, {
        display_name: "My Store",
        notification_url: "https://example.com/hook",
        test_mode: "1"
      })

      expect(result.errors).to be_empty
      reloaded = shop.reload
      expect(reloaded.display_name).to eq("My Store")
      expect(reloaded.notification_url).to eq("https://example.com/hook")
      expect(reloaded.test_mode).to be true
    end

    it "casts test_mode string '0' to false" do
      shop.update!(test_mode: true)
      described_class.call(shop, { test_mode: "0" })
      expect(shop.reload.test_mode).to be false
    end

    it "returns shop with errors when notification_url is not HTTPS" do
      result = described_class.call(shop, { notification_url: "http://insecure.com/hook" })
      expect(result.errors[:notification_url]).to be_present
    end

    it "does not update unpermitted fields (e.g. shop_id)" do
      original_id = shop.shop_id
      described_class.call(shop, { shop_id: "hacked" })
      expect(shop.reload.shop_id).to eq(original_id)
    end
  end
end
