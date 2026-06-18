# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantPolicy, type: :policy do
  let(:psp_admin)   { build(:user, :psp_admin) }
  let(:psp_support) { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin) }
  let(:applicant)   { build(:applicant) }

  describe "index?" do
    it("permits psp_admin")   { expect(described_class.new(psp_admin,   applicant).index?).to be true }
    it("permits psp_support") { expect(described_class.new(psp_support, applicant).index?).to be true }
    it("denies merchant_admin") { expect(described_class.new(merchant_admin, applicant).index?).to be false }
  end

  describe "show?" do
    it("permits psp_admin")   { expect(described_class.new(psp_admin,   applicant).show?).to be true }
    it("permits psp_support") { expect(described_class.new(psp_support, applicant).show?).to be true }
    it("denies merchant_admin") { expect(described_class.new(merchant_admin, applicant).show?).to be false }
  end

  describe "new? / create?" do
    it("permits psp_admin")   { expect(described_class.new(psp_admin,   applicant).new?).to be true }
    it("denies psp_support")  { expect(described_class.new(psp_support, applicant).new?).to be false }
  end

  describe "edit? / update?" do
    it("permits psp_admin")  { expect(described_class.new(psp_admin,   applicant).edit?).to be true }
    it("denies psp_support") { expect(described_class.new(psp_support, applicant).edit?).to be false }
  end

  describe "Scope" do
    before do
      create(:applicant)
      create(:applicant)
    end

    it "psp_admin sees all" do
      scope = ApplicantPolicy::Scope.new(psp_admin, Applicant).resolve
      expect(scope.count).to eq(2)
    end

    it "psp_support sees all" do
      scope = ApplicantPolicy::Scope.new(psp_support, Applicant).resolve
      expect(scope.count).to eq(2)
    end

    it "merchant_admin sees none" do
      scope = ApplicantPolicy::Scope.new(merchant_admin, Applicant).resolve
      expect(scope).to be_empty
    end
  end
end
