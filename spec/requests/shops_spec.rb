require "rails_helper"

RSpec.describe "Shops", type: :request do
  let(:psp_admin)       { create(:user, :psp_admin) }
  let(:psp_support)     { create(:user, :psp_support) }
  let(:merchant_admin)  { create(:user, :merchant_admin, shop_id: "shop_abc") }
  let(:merchant_viewer) { create(:user, :merchant_viewer, shop_id: "shop_abc") }

  let!(:shop)       { create(:shop, shop_id: "shop_abc", name: "Acme Store") }
  let!(:other_shop) { create(:shop, shop_id: "shop_xyz", name: "Other Store") }

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

      it "returns 403" do
        get shops_path
        expect(response).to have_http_status(:forbidden)
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

      it "shows own shop" do
        get shop_path(shop)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
      end

      it "returns 403 for another shop" do
        get shop_path(other_shop)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "shows own shop" do
        get shop_path(shop)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "PATCH /shops/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "updates notification_url and redirects" do
        patch shop_path(shop), params: { shop: { notification_url: "https://example.com/webhooks" } }
        expect(response).to redirect_to(shop_path(shop))
        expect(shop.reload.notification_url).to eq("https://example.com/webhooks")
      end

      it "rejects non-HTTPS notification_url" do
        patch shop_path(shop), params: { shop: { notification_url: "http://example.com/webhooks" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        patch shop_path(shop), params: { shop: { notification_url: "https://example.com/webhooks" } }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        patch shop_path(shop), params: { shop: { notification_url: "https://example.com/webhooks" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
