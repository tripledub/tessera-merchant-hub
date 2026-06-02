# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tessera::Merchant, type: :model do
  subject(:merchant) { build(:tessera_merchant) }

  describe "table" do
    it "uses the merchants table" do
      expect(described_class.table_name).to eq("merchants")
    end
  end

  describe "associations" do
    it "has many shops keyed by merchant_id" do
      expect(merchant).to have_many(:shops)
        .class_name("Tessera::Shop").with_foreign_key(:merchant_id).with_primary_key(:merchant_id)
    end
  end

  describe "read-only behaviour" do
    let(:persisted) { create(:tessera_merchant) }

    it "raises on save" do
      expect { persisted.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises on destroy" do
      expect { persisted.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
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
