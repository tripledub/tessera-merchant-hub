# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycDocumentPolicy, type: :policy do
  let(:psp_admin)      { build(:user, :psp_admin) }
  let(:psp_support)    { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin) }
  let(:document)       { build(:kyc_document) }

  it("psp_admin can create")      { expect(described_class.new(psp_admin,      document).create?).to be true }
  it("psp_support cannot create") { expect(described_class.new(psp_support,    document).create?).to be false }
  it("psp_support can show")      { expect(described_class.new(psp_support,    document).show?).to be true }
  it("merchant_admin cannot show") { expect(described_class.new(merchant_admin, document).show?).to be false }
end
