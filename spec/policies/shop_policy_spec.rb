require "rails_helper"

RSpec.describe ShopPolicy, type: :policy do
  ShopStub = Struct.new(:merchant_id) unless defined?(ShopStub)

  let(:psp_admin)       { build_stubbed(:user, :psp_admin) }
  let(:psp_support)     { build_stubbed(:user, :psp_support) }
  let(:merchant_admin)  { build_stubbed(:user, :merchant_admin, merchant_id: "m1") }
  let(:merchant_viewer) { build_stubbed(:user, :merchant_viewer, merchant_id: "m1") }

  let(:own_shop)   { ShopStub.new("m1") }
  let(:other_shop) { ShopStub.new("m2") }

  describe "index?" do
    it "permits all authenticated roles (scope filters)" do
      expect(described_class.new(psp_admin, ShopStub)).to permit_action(:index)
      expect(described_class.new(psp_support, ShopStub)).to permit_action(:index)
      expect(described_class.new(merchant_admin, ShopStub)).to permit_action(:index)
      expect(described_class.new(merchant_viewer, ShopStub)).to permit_action(:index)
    end
  end

  describe "show?" do
    it "permits psp roles for any shop" do
      expect(described_class.new(psp_admin, other_shop)).to permit_action(:show)
      expect(described_class.new(psp_support, other_shop)).to permit_action(:show)
    end

    it "permits merchant roles for a shop in their merchant" do
      expect(described_class.new(merchant_admin, own_shop)).to permit_action(:show)
      expect(described_class.new(merchant_viewer, own_shop)).to permit_action(:show)
    end

    it "denies merchant roles for another merchant's shop" do
      expect(described_class.new(merchant_admin, other_shop)).to forbid_action(:show)
      expect(described_class.new(merchant_viewer, other_shop)).to forbid_action(:show)
    end
  end

  describe "create?" do
    it "permits psp_admin and merchant_admin" do
      expect(described_class.new(psp_admin, ShopStub)).to permit_action(:create)
      expect(described_class.new(merchant_admin, ShopStub)).to permit_action(:create)
    end

    it "denies psp_support and merchant_viewer" do
      expect(described_class.new(psp_support, ShopStub)).to forbid_action(:create)
      expect(described_class.new(merchant_viewer, ShopStub)).to forbid_action(:create)
    end
  end

  describe "update?" do
    it "permits psp_admin for any shop" do
      expect(described_class.new(psp_admin, other_shop)).to permit_action(:update)
    end

    it "permits merchant_admin for their own merchant's shop" do
      expect(described_class.new(merchant_admin, own_shop)).to permit_action(:update)
    end

    it "denies merchant_admin for another merchant's shop" do
      expect(described_class.new(merchant_admin, other_shop)).to forbid_action(:update)
    end

    it "denies psp_support and merchant_viewer" do
      expect(described_class.new(psp_support, own_shop)).to forbid_action(:update)
      expect(described_class.new(merchant_viewer, own_shop)).to forbid_action(:update)
    end
  end

  describe "generate_credential?" do
    it "permits psp_admin for any shop" do
      expect(described_class.new(psp_admin, other_shop)).to permit_action(:generate_credential)
    end

    it "permits merchant_admin for their own merchant's shop" do
      expect(described_class.new(merchant_admin, own_shop)).to permit_action(:generate_credential)
    end

    it "denies merchant_admin for another merchant's shop" do
      expect(described_class.new(merchant_admin, other_shop)).to forbid_action(:generate_credential)
    end

    it "denies psp_support and merchant_viewer" do
      expect(described_class.new(psp_support, own_shop)).to forbid_action(:generate_credential)
      expect(described_class.new(merchant_viewer, own_shop)).to forbid_action(:generate_credential)
    end
  end
end
