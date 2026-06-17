# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycPrincipalPolicy, type: :policy do
  let(:psp_admin)      { build(:user, :psp_admin) }
  let(:psp_support)    { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin) }
  let(:principal)      { build(:kyc_principal) }

  it("psp_admin can create")     { expect(described_class.new(psp_admin,   principal).create?).to be true }
  it("psp_support cannot create") { expect(described_class.new(psp_support, principal).create?).to be false }
  it("psp_admin can destroy")    { expect(described_class.new(psp_admin,   principal).destroy?).to be true }
  it("psp_support cannot destroy") { expect(described_class.new(psp_support, principal).destroy?).to be false }
  it("psp_support can show")     { expect(described_class.new(psp_support, principal).show?).to be true }
  it("merchant_admin cannot show") { expect(described_class.new(merchant_admin, principal).show?).to be false }
end
