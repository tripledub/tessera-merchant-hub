# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessingStatementPolicy, type: :policy do
  let(:psp_admin)      { build(:user, :psp_admin) }
  let(:psp_support)    { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin) }

  it("psp_admin can create")      { expect(described_class.new(psp_admin,   build(:processing_statement)).create?).to be true }
  it("psp_support cannot create") { expect(described_class.new(psp_support, build(:processing_statement)).create?).to be false }
  it("psp_support can show")      { expect(described_class.new(psp_support, build(:processing_statement)).show?).to be true }
  it("merchant_admin cannot show") { expect(described_class.new(merchant_admin, build(:processing_statement)).show?).to be false }

  describe "#update?" do
    it "allows PSP admins to map uploaded or errored statements" do
      expect(described_class.new(psp_admin, build(:processing_statement, status: :uploaded))).to be_update
      expect(described_class.new(psp_admin, build(:processing_statement, status: :error))).to be_update
    end

    it "denies mapping locked statements and non-admin users" do
      %i[mapped processed].each do |status|
        expect(described_class.new(psp_admin, build(:processing_statement, status: status))).not_to be_update
      end

      expect(described_class.new(psp_support, build(:processing_statement, status: :uploaded))).not_to be_update
    end
  end

  describe "#destroy?" do
    it "allows PSP admins to remove errored statements" do
      expect(described_class.new(psp_admin, build(:processing_statement, status: :error))).to be_destroy
    end

    it "denies removal before or after an error, and to non-admin users" do
      %i[uploaded mapped processed].each do |status|
        expect(described_class.new(psp_admin, build(:processing_statement, status: status))).not_to be_destroy
      end

      expect(described_class.new(psp_support, build(:processing_statement, status: :error))).not_to be_destroy
    end
  end

  describe "#export?" do
    it "allows a processed statement" do
      statement = build(:processing_statement, status: :processed)
      expect(described_class.new(psp_admin, statement).export?).to be true
    end

    it "denies a statement that isn't processed yet (queued, mapped, or errored)" do
      %i[uploaded mapped error].each do |status|
        statement = build(:processing_statement, status: status)
        expect(described_class.new(psp_admin, statement).export?).to be false
      end
    end
  end
end
