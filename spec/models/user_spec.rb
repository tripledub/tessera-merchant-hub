require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }

    it "requires merchant_id for merchant roles" do
      user = build(:user, :merchant_admin, merchant_id: nil)
      expect(user).not_to be_valid
      expect(user.errors[:merchant_id]).to include("can't be blank")
    end

    it "does not require merchant_id for PSP roles" do
      user = build(:user, :psp_admin, merchant_id: nil)
      expect(user).to be_valid
    end
  end

  describe "#accessible_shop_ids" do
    it "returns nil (unscoped) for PSP roles" do
      expect(build(:user, :psp_admin).accessible_shop_ids).to be_nil
    end

    it "returns the shop_ids under the user's merchant for merchant roles" do
      user = create(:user, :merchant_admin, merchant_id: "merch_x")
      create(:tessera_shop, merchant_id: "merch_x", shop_id: "shop_a")
      create(:tessera_shop, merchant_id: "merch_x", shop_id: "shop_b")
      create(:tessera_shop, merchant_id: "merch_other", shop_id: "shop_c")

      expect(user.accessible_shop_ids).to contain_exactly("shop_a", "shop_b")
    end
  end

  describe "roles" do
    it { is_expected.to define_enum_for(:role).with_values(psp_admin: 0, psp_support: 1, merchant_admin: 2, merchant_viewer: 3) }

    it "defaults to psp_admin" do
      expect(build(:user).role).to eq("psp_admin")
    end
  end

  describe "#psp_role?" do
    it "returns true for psp_admin and psp_support" do
      expect(build(:user, :psp_admin)).to be_psp_role
      expect(build(:user, :psp_support)).to be_psp_role
    end

    it "returns false for merchant roles" do
      expect(build(:user, :merchant_admin, merchant_id: "m1")).not_to be_psp_role
      expect(build(:user, :merchant_viewer, merchant_id: "m1")).not_to be_psp_role
    end
  end

  describe "#merchant_role?" do
    it "returns true for merchant_admin and merchant_viewer" do
      expect(build(:user, :merchant_admin, merchant_id: "m1")).to be_merchant_role
      expect(build(:user, :merchant_viewer, merchant_id: "m1")).to be_merchant_role
    end

    it "returns false for PSP roles" do
      expect(build(:user, :psp_admin)).not_to be_merchant_role
      expect(build(:user, :psp_support)).not_to be_merchant_role
    end
  end

  describe "lockable" do
    it "locks the account after too many failed sign-in attempts" do
      user = create(:user)
      Devise.maximum_attempts.times { user.valid_for_authentication? { false } }
      expect(user.reload).to be_access_locked
    end
  end
end
