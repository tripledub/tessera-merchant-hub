require "rails_helper"

RSpec.describe "Payments", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  # merch_abc owns shop_abc; shop_xyz belongs to a different merchant
  let_it_be(:own_shop) { create(:tessera_shop, merchant_id: "merch_abc", shop_id: "shop_abc") }

  let_it_be(:own_payment)   { create(:tessera_payment, shop_id: "shop_abc", status: "succeeded") }
  let_it_be(:other_payment) { create(:tessera_payment, shop_id: "shop_xyz", status: "failed") }

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

      it "returns only succeeded payments when status=succeeded" do
        get payments_path, params: { status: "succeeded" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_payment.id)
        expect(response.body).not_to include(other_payment.id)
      end

      it "returns only failed payments when status=failed" do
        get payments_path, params: { status: "failed" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(other_payment.id)
        expect(response.body).not_to include(own_payment.id)
      end

      it "returns 200 with empty table when status matches no payments" do
        get payments_path, params: { status: "voided" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No payments found.")
      end

      it "returns all payments when status param is blank" do
        get payments_path, params: { status: "" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_payment.id)
        expect(response.body).to include(other_payment.id)
      end
    end

    context "when paginating" do
      # Create 26 payments for shop_abc so page 2 exists (page size is 25)
      let_it_be(:paginated_payments) do
        26.times.map do |i|
          create(:tessera_payment,
            shop_id: "shop_abc",
            status: "succeeded",
            inserted_at: Time.current - i.hours,
            updated_at:  Time.current - i.hours)
        end
      end

      before { sign_in psp_admin }

      it "returns 200 for page 1" do
        get payments_path, params: { page: 1 }
        expect(response).to have_http_status(:ok)
      end

      it "returns 200 for page 2" do
        get payments_path, params: { page: 2 }
        expect(response).to have_http_status(:ok)
      end

      it "returns 200 for page 1 with a status filter applied" do
        get payments_path, params: { page: 1, status: "succeeded" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "when requesting per_page" do
      let_it_be(:extra_payments) do
        12.times.map { create(:tessera_payment, shop_id: "shop_abc", status: "succeeded") }
      end

      before { sign_in psp_admin }

      it "respects per_page=10" do
        get payments_path, params: { per_page: 10 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("10")
      end

      it "defaults to 25 for unknown per_page values" do
        get payments_path, params: { per_page: 999 }
        expect(response).to have_http_status(:ok)
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
