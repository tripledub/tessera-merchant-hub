# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentCommentPolicy, type: :policy do
  let(:psp_admin)      { build(:user, :psp_admin) }
  let(:psp_support)    { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin) }
  let(:document)       { build(:kyc_document) }

  it("psp_admin can index")        { expect(described_class.new(psp_admin, document).index?).to be true }
  it("psp_support can index")      { expect(described_class.new(psp_support, document).index?).to be true }
  it("merchant_admin cannot index") { expect(described_class.new(merchant_admin, document).index?).to be false }

  it("psp_admin can create")        { expect(described_class.new(psp_admin, document).create?).to be true }
  it("psp_support can create")      { expect(described_class.new(psp_support, document).create?).to be true }
  it("merchant_admin cannot create") { expect(described_class.new(merchant_admin, document).create?).to be false }
end
