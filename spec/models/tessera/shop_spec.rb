# frozen_string_literal: true

require "rails_helper"

# Tessera::Shop is now an alias for the MH-owned Shop model (ADR-007).
RSpec.describe Tessera::Shop, type: :model do
  it "is the MerchantHub-owned Shop model" do
    expect(described_class).to eq(Shop)
  end

  it "uses the shops table" do
    expect(described_class.table_name).to eq("shops")
  end

  it "is writable" do
    s = create(:tessera_shop)
    expect { s.update!(name: "Updated") }.not_to raise_error
  end

  describe "#to_param" do
    it "uses the shop_id business key" do
      expect(build(:tessera_shop, shop_id: "shop_42").to_param).to eq("shop_42")
    end
  end

  describe ".for_merchant" do
    it "returns shops for the given merchant_id" do
      create(:tessera_shop, merchant_id: "m_a", shop_id: "shop_a")
      create(:tessera_shop, merchant_id: "m_b", shop_id: "shop_b")

      expect(described_class.for_merchant("m_a").pluck(:shop_id)).to contain_exactly("shop_a")
    end
  end
end
