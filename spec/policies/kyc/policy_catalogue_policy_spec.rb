# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PolicyCataloguePolicy do
  subject(:policy) { described_class.new(user, :policy_catalogue) }

  context "with a PSP admin" do
    let(:user) { build(:user, :psp_admin) }

    it { is_expected.to permit_action(:index) }
  end

  context "with PSP support" do
    let(:user) { build(:user, :psp_support) }

    it { is_expected.to permit_action(:index) }
  end

  context "with a merchant user" do
    let(:user) { build(:user, :merchant_admin) }

    it { is_expected.to forbid_action(:index) }
  end
end
