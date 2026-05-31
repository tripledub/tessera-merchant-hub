require "rails_helper"

RSpec.describe "Payment Actions", type: :request do
  let(:merchant_admin)  { create(:user, :merchant_admin, shop_id: "shop_abc") }
  let(:merchant_viewer) { create(:user, :merchant_viewer, shop_id: "shop_abc") }
  let(:psp_admin)       { create(:user, :psp_admin) }

  let!(:succeeded_payment) { create(:tessera_payment, shop_id: "shop_abc", status: "succeeded") }
  let!(:authorized_payment) { create(:tessera_payment, shop_id: "shop_abc", status: "authorized") }
  let!(:other_payment)  { create(:tessera_payment, shop_id: "shop_xyz", status: "succeeded") }

  let(:refund_success_body) { { "id" => SecureRandom.uuid, "status" => "refunded" }.to_json }
  let(:void_success_body)   { { "id" => SecureRandom.uuid, "status" => "voided" }.to_json }

  describe "POST /payments/:id/refund" do
    context "when unauthenticated" do
      it "redirects to sign in" do
        post refund_payment_path(succeeded_payment.id)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "calls tessera-core and redirects to payment with success notice" do
        stub_request(:post, %r{/v1/payments/.+/refunds})
          .to_return(status: 200, body: refund_success_body, headers: { "Content-Type" => "application/json" })

        post refund_payment_path(succeeded_payment.id), params: { amount: 1000 }

        expect(response).to redirect_to(payment_path(succeeded_payment.id))
        follow_redirect!
        expect(response.body).to include("Refund submitted successfully")
      end

      it "shows inline error when tessera-core returns 422" do
        stub_request(:post, %r{/v1/payments/.+/refunds})
          .to_return(status: 422, body: { "error" => "Refund declined by acquirer" }.to_json,
                     headers: { "Content-Type" => "application/json" })

        post refund_payment_path(succeeded_payment.id), params: { amount: 1000 }

        expect(response).to redirect_to(payment_path(succeeded_payment.id))
        follow_redirect!
        expect(response.body).to include("Refund failed")
      end

      it "returns 403 for another shop's payment" do
        post refund_payment_path(other_payment.id), params: { amount: 1000 }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        post refund_payment_path(succeeded_payment.id), params: { amount: 1000 }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "can refund any shop's payment" do
        stub_request(:post, %r{/v1/payments/.+/refunds})
          .to_return(status: 200, body: refund_success_body, headers: { "Content-Type" => "application/json" })

        post refund_payment_path(other_payment.id), params: { amount: 1000 }
        expect(response).to redirect_to(payment_path(other_payment.id))
      end
    end
  end

  describe "POST /payments/:id/void" do
    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "calls tessera-core and redirects with success notice" do
        stub_request(:post, %r{/v1/payments/.+/void})
          .to_return(status: 200, body: void_success_body, headers: { "Content-Type" => "application/json" })

        post void_payment_path(authorized_payment.id)

        expect(response).to redirect_to(payment_path(authorized_payment.id))
        follow_redirect!
        expect(response.body).to include("Payment voided successfully")
      end

      it "shows error when tessera-core fails" do
        stub_request(:post, %r{/v1/payments/.+/void})
          .to_return(status: 422, body: { "error" => "Cannot void" }.to_json,
                     headers: { "Content-Type" => "application/json" })

        post void_payment_path(authorized_payment.id)

        expect(response).to redirect_to(payment_path(authorized_payment.id))
        follow_redirect!
        expect(response.body).to include("Void failed")
      end

      it "returns 403 for another shop's payment" do
        post void_payment_path(other_payment.id)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        post void_payment_path(authorized_payment.id)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
