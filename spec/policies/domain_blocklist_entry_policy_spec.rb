# frozen_string_literal: true

require "rails_helper"

RSpec.describe DomainBlocklistEntryPolicy, type: :policy do
  let(:psp_admin)      { build(:user, :psp_admin) }
  let(:psp_support)    { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin) }
  let(:entry)          { build(:domain_blocklist_entry) }

  %i[index? create? destroy?].each do |action|
    it("psp_admin can #{action}")           { expect(described_class.new(psp_admin, entry).public_send(action)).to be true }
    it("psp_support cannot #{action}")      { expect(described_class.new(psp_support, entry).public_send(action)).to be false }
    it("merchant_admin cannot #{action}")   { expect(described_class.new(merchant_admin, entry).public_send(action)).to be false }
  end
end
