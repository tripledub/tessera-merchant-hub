# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchants", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer){ create(:user, :merchant_viewer, merchant_id: "merch_abc") }
  let_it_be(:other_admin)    { create(:user, :merchant_admin, merchant_id: "merch_xyz") }

  let_it_be(:merchant_abc) { create(:merchant, merchant_id: "merch_abc", name: "Acme Corp") }
  let_it_be(:merchant_xyz) { create(:merchant, merchant_id: "merch_xyz", name: "XYZ Ltd") }

  describe "GET /merchants/:id/edit" do
    context "when signed in as merchant_admin (own merchant)" do
      before { sign_in merchant_admin }

      it "returns 200" do
        get edit_merchant_path(merchant_abc)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 for any merchant" do
        get edit_merchant_path(merchant_xyz)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403 (cannot edit, only view)" do
        get edit_merchant_path(merchant_abc)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_admin (other merchant)" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get edit_merchant_path(merchant_xyz)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get edit_merchant_path(merchant_abc)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get edit_merchant_path(merchant_abc)
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /merchants" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 and lists all merchants" do
        get merchants_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Corp")
        expect(response.body).to include("XYZ Ltd")
      end

      it "filters by name query" do
        get merchants_path, params: { q: "Acme" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Corp")
        expect(response.body).not_to include("XYZ Ltd")
      end

      it "filters by merchant_id query" do
        get merchants_path, params: { q: "merch_xyz" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("XYZ Ltd")
        expect(response.body).not_to include("Acme Corp")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200" do
        get merchants_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get merchants_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get merchants_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /merchants/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 for any merchant" do
        get merchant_path(merchant_abc)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Corp")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200" do
        get merchant_path(merchant_abc)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin (own merchant)" do
      before { sign_in merchant_admin }

      it "returns 200" do
        get merchant_path(merchant_abc)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin (other merchant)" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get merchant_path(merchant_xyz)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get merchant_path(merchant_abc)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /merchants/:id" do
    context "when signed in as merchant_admin (own merchant)" do
      before { sign_in merchant_admin }

      it "updates profile and redirects to show" do
        patch merchant_path(merchant_abc), params: {
          merchant: { contact_email: "billing@acme.com", city: "London", country_code: "GB" }
        }
        expect(response).to redirect_to(merchant_path(merchant_abc))
        expect(merchant_abc.reload.contact_email).to eq("billing@acme.com")
      end

      it "re-renders edit with 422 on invalid email" do
        patch merchant_path(merchant_abc), params: {
          merchant: { contact_email: "not-an-email" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when signed in as merchant_admin (other merchant)" do
      before { sign_in merchant_admin }

      it "returns 403" do
        patch merchant_path(merchant_xyz), params: { merchant: { city: "London" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
