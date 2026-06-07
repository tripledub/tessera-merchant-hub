# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shop, type: :model do
  subject(:shop) { build(:shop) }

  it { is_expected.to validate_presence_of(:shop_id) }
  it { is_expected.to validate_uniqueness_of(:shop_id) }
  it { is_expected.to validate_presence_of(:merchant_id) }
  it { is_expected.to validate_presence_of(:integration_account_id) }
  it { is_expected.to validate_presence_of(:name) }

  it "belongs to merchant" do
    expect(shop).to belong_to(:merchant)
      .with_foreign_key(:merchant_id)
      .with_primary_key(:merchant_id)
      .optional
  end

  describe "#to_param" do
    it "uses shop_id in URLs" do
      expect(build(:shop, shop_id: "shop_42").to_param).to eq("shop_42")
    end
  end

  describe ".for_merchant" do
    before do
      create(:shop, merchant_id: "m_a", shop_id: "shop_a")
      create(:shop, merchant_id: "m_b", shop_id: "shop_b")
    end

    it "filters by merchant_id" do
      expect(described_class.for_merchant("m_a").pluck(:shop_id)).to eq([ "shop_a" ])
    end
  end

  describe "persistence" do
    let(:persisted) { create(:shop) }

    it "is writable" do
      expect(persisted).not_to be_readonly
    end
  end
end
