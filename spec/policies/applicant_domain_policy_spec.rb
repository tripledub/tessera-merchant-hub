# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantDomainPolicy, type: :policy do
  let(:psp_admin)      { build(:user, :psp_admin) }
  let(:psp_support)    { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin) }
  let(:applicant_domain) { build(:applicant_domain) }

  it("psp_admin can create")       { expect(described_class.new(psp_admin, applicant_domain).create?).to be true }
  it("psp_support cannot create")  { expect(described_class.new(psp_support, applicant_domain).create?).to be false }
  it("psp_admin can destroy")      { expect(described_class.new(psp_admin, applicant_domain).destroy?).to be true }
  it("psp_support cannot destroy") { expect(described_class.new(psp_support, applicant_domain).destroy?).to be false }
  it("psp_admin can accept")       { expect(described_class.new(psp_admin, applicant_domain).accept?).to be true }
  it("psp_support cannot accept")  { expect(described_class.new(psp_support, applicant_domain).accept?).to be false }
  it("merchant_admin cannot accept") { expect(described_class.new(merchant_admin, applicant_domain).accept?).to be false }
  it("psp_admin can reject")       { expect(described_class.new(psp_admin, applicant_domain).reject?).to be true }
  it("psp_support cannot reject")  { expect(described_class.new(psp_support, applicant_domain).reject?).to be false }
  it("merchant_admin cannot reject") { expect(described_class.new(merchant_admin, applicant_domain).reject?).to be false }
  it("psp_support can show")       { expect(described_class.new(psp_support, applicant_domain).show?).to be true }
  it("merchant_admin cannot show") { expect(described_class.new(merchant_admin, applicant_domain).show?).to be false }
end
