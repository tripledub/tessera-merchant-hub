require "rails_helper"

RSpec.describe "Payments", type: :request do
  let(:psp_admin)      { create(:user, :psp_admin) }
  let(:merchant_admin) { create(:user, :merchant_admin, shop_id: "shop_abc") }
  let(:merchant_viewer) { create(:user, :merchant_viewer, shop_id: "shop_abc") }

  let!(:own_payment)   { create(:tessera_payment, shop_id: "shop_abc", status: "succeeded") }
  let!(:other_payment) { create(:tessera_payment, shop_id: "shop_xyz", status: "failed") }

  describe "GET /payments" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 and lists all payments" do
        get payments_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_payment.id)
        expect(response.body).to include(other_payment.id)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 200 and lists only own shop payments" do
        get payments_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_payment.id)
        expect(response.body).not_to include(other_payment.id)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 200 and lists only own shop payments" do
        get payments_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_payment.id)
        expect(response.body).not_to include(other_payment.id)
      end
    end

    context "when filtering by status" do
      before { sign_in psp_admin }

      it "returns only matching payments" do
        get payments_path, params: { status: "failed" }
        expect(response.body).to include(other_payment.id)
        expect(response.body).not_to include(own_payment.id)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get payments_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /payments/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "shows any payment" do
        get payment_path(other_payment.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(other_payment.id)
      end
    end

    context "when merchant_admin views own shop payment" do
      before { sign_in merchant_admin }

      it "returns 200" do
        get payment_path(own_payment.id)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when merchant_admin views another shop's payment" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get payment_path(other_payment.id)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
