# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserPolicy, type: :policy do
  let(:psp_admin)       { build_stubbed(:user, :psp_admin) }
  let(:psp_support)     { build_stubbed(:user, :psp_support) }
  let(:merchant_admin)  { build_stubbed(:user, :merchant_admin, merchant_id: "m1") }
  let(:merchant_viewer) { build_stubbed(:user, :merchant_viewer, merchant_id: "m1") }

  let(:same_merchant_user)  { build_stubbed(:user, :merchant_viewer, merchant_id: "m1") }
  let(:other_merchant_user) { build_stubbed(:user, :merchant_viewer, merchant_id: "m2") }

  describe "index?" do
    it("permits psp_admin")      { expect(described_class.new(psp_admin, User)).to permit_action(:index) }
    it("permits merchant_admin") { expect(described_class.new(merchant_admin, User)).to permit_action(:index) }
    it("denies psp_support")     { expect(described_class.new(psp_support, User)).to forbid_action(:index) }
    it("denies merchant_viewer") { expect(described_class.new(merchant_viewer, User)).to forbid_action(:index) }
  end

  describe "invite?" do
    it("permits psp_admin")      { expect(described_class.new(psp_admin, User.new)).to permit_action(:invite) }
    it("permits merchant_admin") { expect(described_class.new(merchant_admin, User.new)).to permit_action(:invite) }
    it("denies psp_support")     { expect(described_class.new(psp_support, User.new)).to forbid_action(:invite) }
    it("denies merchant_viewer") { expect(described_class.new(merchant_viewer, User.new)).to forbid_action(:invite) }
  end

  describe "deactivate?" do
    it "permits psp_admin on any user" do
      expect(described_class.new(psp_admin, other_merchant_user)).to permit_action(:deactivate)
    end

    it "permits merchant_admin on same-merchant user" do
      expect(described_class.new(merchant_admin, same_merchant_user)).to permit_action(:deactivate)
    end

    it "denies merchant_admin on other-merchant user" do
      expect(described_class.new(merchant_admin, other_merchant_user)).to forbid_action(:deactivate)
    end

    it "denies merchant_admin deactivating themselves" do
      expect(described_class.new(merchant_admin, merchant_admin)).to forbid_action(:deactivate)
    end

    it "denies psp_admin deactivating themselves" do
      expect(described_class.new(psp_admin, psp_admin)).to forbid_action(:deactivate)
    end

    it "denies merchant_viewer" do
      expect(described_class.new(merchant_viewer, same_merchant_user)).to forbid_action(:deactivate)
    end
  end

  describe "unlock?" do
    it("permits psp_admin")      { expect(described_class.new(psp_admin, same_merchant_user)).to permit_action(:unlock) }
    it("denies merchant_admin")  { expect(described_class.new(merchant_admin, same_merchant_user)).to forbid_action(:unlock) }
    it("denies psp_support")     { expect(described_class.new(psp_support, same_merchant_user)).to forbid_action(:unlock) }
  end

  describe "update_role?" do
    it("permits psp_admin")      { expect(described_class.new(psp_admin, same_merchant_user)).to permit_action(:update_role) }
    it("denies merchant_admin")  { expect(described_class.new(merchant_admin, same_merchant_user)).to forbid_action(:update_role) }
  end

  describe "Scope" do
    before do
      create(:user, :merchant_admin, merchant_id: "m1")
      create(:user, :merchant_viewer, merchant_id: "m1")
      create(:user, :merchant_admin, merchant_id: "m2")
    end

    it "psp_admin sees all users" do
      scope = UserPolicy::Scope.new(psp_admin, User).resolve
      expect(scope.count).to eq(User.count)
    end

    it "merchant_admin sees only own merchant users" do
      scope = UserPolicy::Scope.new(merchant_admin, User).resolve
      expect(scope.map(&:merchant_id).uniq).to contain_exactly("m1")
    end

    it "merchant_viewer sees nothing" do
      scope = UserPolicy::Scope.new(merchant_viewer, User).resolve
      expect(scope).to be_empty
    end
  end
end
