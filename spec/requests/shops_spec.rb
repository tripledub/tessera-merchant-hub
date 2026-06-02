require "rails_helper"

RSpec.describe "Shops", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:psp_support)     { create(:user, :psp_support) }
  let_it_be(:merchant_admin)  { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  let_it_be(:own_shop)   { create(:tessera_shop, merchant_id: "merch_abc", shop_id: "shop_abc", name: "Acme Store") }
  let_it_be(:other_shop) { create(:tessera_shop, merchant_id: "merch_xyz", shop_id: "shop_xyz", name: "Other Store") }

  describe "GET /shops" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 and lists all shops" do
        get shops_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
        expect(response.body).to include("Other Store")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200 and lists all shops" do
        get shops_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "lists only the merchant's own shops" do
        get shops_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
        expect(response.body).not_to include("Other Store")
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get shops_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /shops/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "shows any shop" do
        get shop_path(other_shop)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Other Store")
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "shows a shop in their merchant" do
        get shop_path(own_shop)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
      end

      it "returns 403 for another merchant's shop" do
        get shop_path(other_shop)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "shows a shop in their merchant" do
        get shop_path(own_shop)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
