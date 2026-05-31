require "rails_helper"

RSpec.describe UserPolicy, type: :policy do
  let(:psp_admin)       { build_stubbed(:user, :psp_admin) }
  let(:psp_support)     { build_stubbed(:user, :psp_support) }
  let(:merchant_admin)  { build_stubbed(:user, :merchant_admin, shop_id: "shop_1") }
  let(:merchant_viewer) { build_stubbed(:user, :merchant_viewer, shop_id: "shop_1") }

  let(:same_shop_user)  { build_stubbed(:user, :merchant_viewer, shop_id: "shop_1") }
  let(:other_shop_user) { build_stubbed(:user, :merchant_viewer, shop_id: "shop_2") }

  describe "index?" do
    it "permits psp_admin" do
      expect(described_class.new(psp_admin, User)).to permit_action(:index)
    end

    it "permits merchant_admin" do
      expect(described_class.new(merchant_admin, User)).to permit_action(:index)
    end

    it "denies psp_support" do
      expect(described_class.new(psp_support, User)).to forbid_action(:index)
    end

    it "denies merchant_viewer" do
      expect(described_class.new(merchant_viewer, User)).to forbid_action(:index)
    end
  end

  describe "create?" do
    it "permits psp_admin" do
      expect(described_class.new(psp_admin, User.new)).to permit_action(:create)
    end

    it "permits merchant_admin" do
      expect(described_class.new(merchant_admin, User.new)).to permit_action(:create)
    end

    it "denies psp_support" do
      expect(described_class.new(psp_support, User.new)).to forbid_action(:create)
    end

    it "denies merchant_viewer" do
      expect(described_class.new(merchant_viewer, User.new)).to forbid_action(:create)
    end
  end

  describe "update?" do
    it "permits psp_admin for any user" do
      expect(described_class.new(psp_admin, other_shop_user)).to permit_action(:update)
    end

    it "permits merchant_admin for same shop users" do
      expect(described_class.new(merchant_admin, same_shop_user)).to permit_action(:update)
    end

    it "denies merchant_admin for other shop users" do
      expect(described_class.new(merchant_admin, other_shop_user)).to forbid_action(:update)
    end

    it "denies merchant_viewer" do
      expect(described_class.new(merchant_viewer, same_shop_user)).to forbid_action(:update)
    end
  end

  describe "destroy?" do
    it "permits psp_admin" do
      expect(described_class.new(psp_admin, other_shop_user)).to permit_action(:destroy)
    end

    it "denies merchant_admin" do
      expect(described_class.new(merchant_admin, same_shop_user)).to forbid_action(:destroy)
    end
  end
end
