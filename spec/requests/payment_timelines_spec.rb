require "rails_helper"

RSpec.describe "Payment Timelines", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  # merch_abc owns shop_abc
  let_it_be(:own_shop) { create(:tessera_shop, merchant_id: "merch_abc", shop_id: "shop_abc") }

  let_it_be(:payment)       { create(:tessera_payment, shop_id: "shop_abc") }
  let_it_be(:other_payment) { create(:tessera_payment, shop_id: "shop_xyz") }

  let_it_be(:system_event) do
    create(:tessera_audit_event, payment: payment,
      event_type: "acquirer_request", actor: "system",
      outcome: "success", occurred_at: 1.hour.ago)
  end

  let_it_be(:merchant_event) do
    create(:tessera_audit_event, payment: payment,
      event_type: "refund_requested", actor: "merchant",
      outcome: "success", occurred_at: 30.minutes.ago)
  end

  let_it_be(:webhook_delivery) do
    create(:tessera_webhook_delivery, payment: payment,
      status: "delivered", attempts: 1)
  end

  describe "GET /payments/:id/timeline" do
    context "when unauthenticated" do
      it "redirects to sign in" do
        get payment_timeline_path(payment.id)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get payment_timeline_path(payment.id)
        expect(response).to have_http_status(:ok)
      end

      it "shows all events including system actor events" do
        get payment_timeline_path(payment.id)
        expect(response.body).to include("Acquirer request")
        expect(response.body).to include("Refund requested")
      end

      it "shows webhook delivery status" do
        get payment_timeline_path(payment.id)
        expect(response.body).to include("delivered")
      end

      it "shows events in chronological order" do
        get payment_timeline_path(payment.id)
        system_pos   = response.body.index("Acquirer request")
        merchant_pos = response.body.index("Refund requested")
        expect(system_pos).to be < merchant_pos
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200 and shows all events including system events" do
        get payment_timeline_path(payment.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acquirer request")
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 200 for own shop payment" do
        get payment_timeline_path(payment.id)
        expect(response).to have_http_status(:ok)
      end

      it "hides internal system events but shows merchant events" do
        get payment_timeline_path(payment.id)
        expect(response.body).not_to include("Acquirer request")
        expect(response.body).to include("Refund requested")
      end

      it "returns 403 for another shop's payment" do
        get payment_timeline_path(other_payment.id)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 200 for own shop payment" do
        get payment_timeline_path(payment.id)
        expect(response).to have_http_status(:ok)
      end

      it "hides internal system events" do
        get payment_timeline_path(payment.id)
        expect(response.body).not_to include("Acquirer request")
      end
    end
  end
end
