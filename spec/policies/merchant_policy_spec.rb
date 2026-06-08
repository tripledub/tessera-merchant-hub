# frozen_string_literal: true

require "rails_helper"

RSpec.describe MerchantPolicy, type: :policy do
  let(:psp_admin)       { build(:user, :psp_admin) }
  let(:psp_support)     { build(:user, :psp_support) }
  let(:merchant_admin)  { build(:user, :merchant_admin, merchant_id: "merch_abc") }
  let(:merchant_viewer) { build(:user, :merchant_viewer, merchant_id: "merch_abc") }
  let(:own_merchant)    { build(:merchant, merchant_id: "merch_abc") }
  let(:other_merchant)  { build(:merchant, merchant_id: "merch_xyz") }

  describe "new? / create?" do
    it("permits psp_admin")     { expect(described_class.new(psp_admin, Merchant).new?).to be true }
    it("denies psp_support")    { expect(described_class.new(psp_support, Merchant).new?).to be false }
    it("denies merchant_admin") { expect(described_class.new(merchant_admin, Merchant).new?).to be false }
    it("create? matches new?")  { expect(described_class.new(psp_admin, Merchant).create?).to be true }
  end

  describe "index?" do
    it("permits psp_admin")    { expect(described_class.new(psp_admin, Merchant).index?).to be true }
    it("permits psp_support")  { expect(described_class.new(psp_support, Merchant).index?).to be true }
    it("denies merchant_admin") { expect(described_class.new(merchant_admin, Merchant).index?).to be false }
  end

  describe "show?" do
    it("permits psp_admin on any merchant") { expect(described_class.new(psp_admin, other_merchant).show?).to be true }
    it("permits merchant_admin on own")     { expect(described_class.new(merchant_admin, own_merchant).show?).to be true }
    it("denies merchant_admin on other")    { expect(described_class.new(merchant_admin, other_merchant).show?).to be false }
    it("denies merchant_viewer on own")     { expect(described_class.new(merchant_viewer, own_merchant).show?).to be false }
  end

  describe "edit? / update?" do
    it("permits psp_admin on any merchant") { expect(described_class.new(psp_admin, other_merchant).edit?).to be true }
    it("permits merchant_admin on own")     { expect(described_class.new(merchant_admin, own_merchant).edit?).to be true }
    it("denies merchant_admin on other")    { expect(described_class.new(merchant_admin, other_merchant).edit?).to be false }
    it("denies merchant_viewer")            { expect(described_class.new(merchant_viewer, own_merchant).edit?).to be false }
    it("update? matches edit?")             { expect(described_class.new(merchant_admin, own_merchant).update?).to be true }
  end

  describe "Scope" do
    before do
      create(:merchant, merchant_id: "merch_abc")
      create(:merchant, merchant_id: "merch_xyz")
    end

    it "psp_admin sees all" do
      scope = MerchantPolicy::Scope.new(psp_admin, Merchant).resolve
      expect(scope.count).to eq(2)
    end

    it "merchant_admin sees only own merchant" do
      scope = MerchantPolicy::Scope.new(merchant_admin, Merchant).resolve
      expect(scope.map(&:merchant_id)).to contain_exactly("merch_abc")
    end

    it "merchant_viewer sees nothing" do
      scope = MerchantPolicy::Scope.new(merchant_viewer, Merchant).resolve
      expect(scope).to be_empty
    end
  end
end
