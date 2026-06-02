# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tessera::Shop, type: :model do
  subject(:shop) { build(:tessera_shop) }

  describe "table" do
    it "uses the shops table" do
      expect(described_class.table_name).to eq("shops")
    end
  end

  describe "associations" do
    it "belongs to merchant keyed by merchant_id" do
      expect(shop).to belong_to(:merchant).optional
        .class_name("Tessera::Merchant").with_foreign_key(:merchant_id).with_primary_key(:merchant_id)
    end
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

  describe "read-only behaviour" do
    let(:persisted) { create(:tessera_shop) }

    it "raises on save" do
      expect { persisted.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises on destroy" do
      expect { persisted.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
