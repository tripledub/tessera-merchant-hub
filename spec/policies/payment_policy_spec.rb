require "rails_helper"

RSpec.describe PaymentPolicy, type: :policy do
  Payment = Struct.new(:shop_id) unless defined?(Payment)

  let(:psp_admin)       { build_stubbed(:user, :psp_admin) }
  let(:psp_support)     { build_stubbed(:user, :psp_support) }
  let(:merchant_admin)  { build_stubbed(:user, :merchant_admin, shop_id: "shop_1") }
  let(:merchant_viewer) { build_stubbed(:user, :merchant_viewer, shop_id: "shop_1") }

  let(:own_payment)   { Payment.new("shop_1") }
  let(:other_payment) { Payment.new("shop_2") }

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
    it "returns all payments for PSP roles (passes scope through)" do
      ar_scope = Tessera::Payment.all
      scope = PaymentPolicy::Scope.new(psp_admin, ar_scope)
      expect(scope.resolve).to eq(ar_scope)
    end

    it "returns only own shop payments for merchant roles" do
      ar_scope = Tessera::Payment.all
      scope = PaymentPolicy::Scope.new(merchant_admin, ar_scope)
      expect(scope.resolve.to_sql).to include("shop_1")
    end
  end
end
