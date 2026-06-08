# frozen_string_literal: true

require "rails_helper"

RSpec.describe Merchant, type: :model do
  subject(:merchant) { build(:merchant) }

  it { is_expected.to validate_presence_of(:merchant_id) }
  it { is_expected.to validate_uniqueness_of(:merchant_id) }
  it { is_expected.to validate_presence_of(:name) }

  it "has many shops" do
    expect(merchant).to have_many(:shops)
      .with_foreign_key(:merchant_id)
      .with_primary_key(:merchant_id)
  end

  describe "persistence" do
    let(:persisted) { create(:merchant) }

    it "is writable" do
      expect(persisted).not_to be_readonly
    end
  end

  describe "validations — contact_email" do
    it "is valid when blank" do
      merchant = build(:merchant, contact_email: "")
      expect(merchant).to be_valid
    end

    it "is valid with a well-formed email" do
      merchant = build(:merchant, contact_email: "billing@acme.com")
      expect(merchant).to be_valid
    end

    it "is invalid with a malformed email" do
      merchant = build(:merchant, contact_email: "not-an-email")
      expect(merchant).not_to be_valid
      expect(merchant.errors[:contact_email]).to be_present
    end
  end

  describe "validations — country_code" do
    it "is valid when blank" do
      merchant = build(:merchant, country_code: nil)
      expect(merchant).to be_valid
    end

    it "upcases the value before validation" do
      merchant = build(:merchant, country_code: "gb")
      merchant.valid?
      expect(merchant.country_code).to eq("GB")
    end

    it "is valid with a 2-letter uppercase code" do
      merchant = build(:merchant, country_code: "GB")
      expect(merchant).to be_valid
    end

    it "is invalid with a 3-letter code" do
      merchant = build(:merchant, country_code: "GBR")
      expect(merchant).not_to be_valid
      expect(merchant.errors[:country_code]).to be_present
    end
  end

  describe "associations" do
    it "groups shops by merchant_id" do
      merchant = create(:merchant, merchant_id: "merch_z")
      create(:shop, merchant_id: "merch_z", shop_id: "shop_z1")
      create(:shop, merchant_id: "merch_other", shop_id: "shop_o1")

      expect(merchant.shops.pluck(:shop_id)).to eq([ "shop_z1" ])
    end
  end

  describe "#to_param" do
    it "returns merchant_id for URL generation" do
      merchant = build(:merchant, merchant_id: "merch_abc")
      expect(merchant.to_param).to eq("merch_abc")
    end
  end
end
