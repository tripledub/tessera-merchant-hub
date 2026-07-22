# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantUserPolicy, type: :policy do
  let(:psp_admin)      { build(:user, :psp_admin) }
  let(:psp_support)    { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin) }
  let(:applicant_user) { build(:applicant_user) }

  it("psp_admin can destroy")      { expect(described_class.new(psp_admin,      applicant_user).destroy?).to be true }
  it("psp_support cannot destroy") { expect(described_class.new(psp_support,    applicant_user).destroy?).to be false }
  it("merchant_admin cannot destroy") { expect(described_class.new(merchant_admin, applicant_user).destroy?).to be false }
end
