require "rails_helper"

RSpec.describe ShopPolicy, type: :policy do
  Shop = Struct.new(:id) unless defined?(Shop)

  let(:psp_admin)       { build_stubbed(:user, :psp_admin) }
  let(:psp_support)     { build_stubbed(:user, :psp_support) }
  let(:merchant_admin)  { build_stubbed(:user, :merchant_admin, shop_id: 1) }
  let(:merchant_viewer) { build_stubbed(:user, :merchant_viewer, shop_id: 1) }

  let(:own_shop)   { Shop.new(1) }
  let(:other_shop) { Shop.new(2) }

  describe "index?" do
    it "permits psp_admin" do
      expect(described_class.new(psp_admin, Shop)).to permit_action(:index)
    end

    it "permits psp_support" do
      expect(described_class.new(psp_support, Shop)).to permit_action(:index)
    end

    it "denies merchant_admin" do
      expect(described_class.new(merchant_admin, Shop)).to forbid_action(:index)
    end

    it "denies merchant_viewer" do
      expect(described_class.new(merchant_viewer, Shop)).to forbid_action(:index)
    end
  end

  describe "show?" do
    it "permits psp roles for any shop" do
      expect(described_class.new(psp_admin, other_shop)).to permit_action(:show)
      expect(described_class.new(psp_support, other_shop)).to permit_action(:show)
    end

    it "permits merchant roles for own shop" do
      expect(described_class.new(merchant_admin, own_shop)).to permit_action(:show)
      expect(described_class.new(merchant_viewer, own_shop)).to permit_action(:show)
    end

    it "denies merchant roles for another shop" do
      expect(described_class.new(merchant_admin, other_shop)).to forbid_action(:show)
      expect(described_class.new(merchant_viewer, other_shop)).to forbid_action(:show)
    end
  end

  describe "update?" do
    it "permits only psp_admin" do
      expect(described_class.new(psp_admin, own_shop)).to permit_action(:update)
    end

    it "denies psp_support" do
      expect(described_class.new(psp_support, own_shop)).to forbid_action(:update)
    end

    it "denies merchant roles" do
      expect(described_class.new(merchant_admin, own_shop)).to forbid_action(:update)
      expect(described_class.new(merchant_viewer, own_shop)).to forbid_action(:update)
    end
  end
end
