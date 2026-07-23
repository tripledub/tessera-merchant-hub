# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingSessionPolicy, type: :policy do
  subject(:policy) { described_class.new(user, build(:onboarding_session)) }

  %i[psp_admin psp_support].each do |role|
    context "with #{role}" do
      let(:user) { build(:user, role) }

      it { expect(policy.index?).to be(true) }
      it { expect(policy.show?).to be(true) }
    end
  end

  context "with a merchant admin" do
    let(:user) { build(:user, :merchant_admin) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
  end

  describe "Scope" do
    let!(:session) { create(:onboarding_session) }

    it "returns all sessions to PSP staff" do
      user = build(:user, :psp_support)

      expect(described_class::Scope.new(user, OnboardingSession).resolve).to contain_exactly(session)
    end

    it "returns no sessions to merchant users" do
      user = build(:user, :merchant_admin)

      expect(described_class::Scope.new(user, OnboardingSession).resolve).to be_empty
    end
  end
end
