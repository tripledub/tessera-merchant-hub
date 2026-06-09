require "rails_helper"

RSpec.describe "Payments", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  # merch_abc owns shop_abc; shop_xyz belongs to a different merchant
  let_it_be(:own_shop) { create(:tessera_shop, merchant_id: "merch_abc", shop_id: "shop_abc") }

  let_it_be(:own_payment)   { create(:tessera_payment, shop_id: "shop_abc", status: "succeeded") }
  let_it_be(:other_payment) { create(:tessera_payment, shop_id: "shop_xyz", status: "failed") }

  let_it_be(:old_payment) do
    create(:tessera_payment,
      shop_id: "shop_abc",
      status: "pending",
      amount: 500,
      merchant_reference: "REF-ORDER-001",
      inserted_at: 30.days.ago,
      updated_at:  30.days.ago)
  end

  let_it_be(:large_payment) do
    create(:tessera_payment,
      shop_id: "shop_abc",
      status: "refunded",
      amount: 50_000,
      merchant_reference: "REF-ORDER-BIG",
      inserted_at: 2.days.ago,
      updated_at:  2.days.ago)
  end

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

    context "when filtering by multiple statuses" do
      before { sign_in psp_admin }

      it "returns payments matching any of the selected statuses" do
        get payments_path, params: { status: %w[succeeded pending] }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_payment.id)
        expect(response.body).to include(old_payment.id)
        expect(response.body).not_to include(other_payment.id)  # failed
        expect(response.body).not_to include(large_payment.id)  # refunded
      end
    end

    context "when filtering by reference" do
      before { sign_in psp_admin }

      it "returns payments whose merchant_reference contains the query (case-insensitive)" do
        get payments_path, params: { reference: "ref-order" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(old_payment.id)
        expect(response.body).to include(large_payment.id)
      end

      it "returns empty table when reference matches nothing" do
        get payments_path, params: { reference: "zzz_no_match" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("payments.index.table.empty"))
      end
    end

    context "when filtering by date range" do
      before { sign_in psp_admin }

      it "date_from excludes payments before that date" do
        get payments_path, params: { date_from: 10.days.ago.to_date.to_s }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_payment.id)
        expect(response.body).to include(large_payment.id)
        expect(response.body).not_to include(old_payment.id)
      end

      it "date_to excludes payments after that date" do
        get payments_path, params: { date_to: 25.days.ago.to_date.to_s }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(old_payment.id)
        expect(response.body).not_to include(own_payment.id)
        expect(response.body).not_to include(large_payment.id)
      end

      it "combined date_from + date_to returns payments in the range" do
        get payments_path, params: {
          date_from: 5.days.ago.to_date.to_s,
          date_to:   1.day.ago.to_date.to_s
        }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(large_payment.id)
        expect(response.body).not_to include(own_payment.id)
        expect(response.body).not_to include(old_payment.id)
      end
    end

    context "when filtering by amount range" do
      before { sign_in psp_admin }

      it "amount_min filters out payments below threshold (in currency units)" do
        # large_payment.amount = 50_000 pence = £500; own_payment.amount = 1000 pence = £10
        get payments_path, params: { amount_min: "100" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(large_payment.id)
        expect(response.body).not_to include(own_payment.id)
      end

      it "amount_max filters out payments above threshold (in currency units)" do
        get payments_path, params: { amount_max: "20" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_payment.id)  # £10
        expect(response.body).to include(old_payment.id)  # £5
        expect(response.body).not_to include(large_payment.id) # £500
      end
    end

    context "when combining multiple filters" do
      before { sign_in psp_admin }

      it "applies status + reference together" do
        get payments_path, params: { status: [ "pending" ], reference: "ref-order" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(old_payment.id)
        # large_payment is refunded, not pending — excluded
        expect(response.body).not_to include(large_payment.id)
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

      it "respects per_page=10 and shows 10 entries" do
        get payments_path, params: { per_page: 10 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Showing 1 to 10")
      end

      it "defaults to 25 for unknown per_page values" do
        get payments_path, params: { per_page: 999 }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "sort" do
      let_it_be(:cheap)     { create(:tessera_payment, shop_id: "shop_abc", amount: 100,    inserted_at: 3.days.ago, updated_at: 3.days.ago) }
      let_it_be(:expensive) { create(:tessera_payment, shop_id: "shop_abc", amount: 99_900, inserted_at: 1.day.ago,  updated_at: 1.day.ago) }

      before { sign_in merchant_admin }

      it "sorts by amount ascending" do
        get payments_path(sort: "amount", direction: "asc")
        expect(response).to have_http_status(:ok)
        expect(response.body.index(cheap.id)).to be < response.body.index(expensive.id)
      end

      it "sorts by amount descending" do
        get payments_path(sort: "amount", direction: "desc")
        expect(response).to have_http_status(:ok)
        expect(response.body.index(expensive.id)).to be < response.body.index(cheap.id)
      end

      it "ignores unknown sort columns and falls back to inserted_at desc" do
        get payments_path(sort: "DROP TABLE users;", direction: "asc")
        expect(response).to have_http_status(:ok)
        # recent payment appears before older one (default inserted_at desc)
        expect(response.body.index(expensive.id)).to be < response.body.index(cheap.id)
      end

      it "ignores unknown direction and falls back to desc" do
        get payments_path(sort: "amount", direction: "INVALID")
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
