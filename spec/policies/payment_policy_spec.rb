require "rails_helper"

RSpec.describe PaymentPolicy, type: :policy do
  Payment = Struct.new(:shop_id) unless defined?(Payment)

  let(:psp_admin)       { build_stubbed(:user, :psp_admin) }
  let(:psp_support)     { build_stubbed(:user, :psp_support) }
  let(:merchant_admin)  { build_stubbed(:user, :merchant_admin, shop_id: 1) }
  let(:merchant_viewer) { build_stubbed(:user, :merchant_viewer, shop_id: 1) }

  let(:own_payment)   { Payment.new(1) }
  let(:other_payment) { Payment.new(2) }

  describe "index?" do
    subject { described_class.new(user, Payment) }

    context "when psp_admin" do
      let(:user) { psp_admin }

      it { is_expected.to permit_action(:index) }
    end

    context "when merchant_admin" do
      let(:user) { merchant_admin }

      it { is_expected.to permit_action(:index) }
    end
  end

  describe "show?" do
    context "when psp role" do
      subject { described_class.new(psp_admin, other_payment) }

      it { is_expected.to permit_action(:show) }
    end

    context "when merchant viewing own shop payment" do
      subject { described_class.new(merchant_admin, own_payment) }

      it { is_expected.to permit_action(:show) }
    end

    context "when merchant viewing another shop's payment" do
      subject { described_class.new(merchant_admin, other_payment) }

      it { is_expected.to forbid_action(:show) }
    end

    context "when merchant_viewer viewing another shop's payment" do
      subject { described_class.new(merchant_viewer, other_payment) }

      it { is_expected.to forbid_action(:show) }
    end
  end

  describe "Scope" do
    let(:all_payments) { [ Payment.new(1), Payment.new(2), Payment.new(3) ] }

    it "returns all payments for PSP roles" do
      scope = PaymentPolicy::Scope.new(psp_admin, all_payments)
      expect(scope.resolve).to eq(all_payments)
    end

    it "returns only own shop payments for merchant roles" do
      scope = PaymentPolicy::Scope.new(merchant_admin, all_payments)
      expect(scope.resolve).to contain_exactly(Payment.new(1))
    end
  end
end
