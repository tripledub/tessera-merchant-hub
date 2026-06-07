# frozen_string_literal: true

require "rails_helper"

# Tessera::Merchant is now an alias for the MH-owned Merchant model (ADR-007).
RSpec.describe Tessera::Merchant, type: :model do
  it "is the MerchantHub-owned Merchant model" do
    expect(described_class).to eq(Merchant)
  end

  it "uses the merchants table" do
    expect(described_class.table_name).to eq("merchants")
  end

  it "is writable" do
    m = create(:tessera_merchant)
    expect { m.update!(name: "Updated") }.not_to raise_error
  end

  describe "shops association" do
    it "returns shops sharing the merchant_id" do
      merchant = create(:tessera_merchant, merchant_id: "merch_z")
      create(:tessera_shop, merchant_id: "merch_z", shop_id: "shop_z1")
      create(:tessera_shop, merchant_id: "merch_other", shop_id: "shop_o1")

      expect(merchant.shops.pluck(:shop_id)).to contain_exactly("shop_z1")
    end
  end
end
