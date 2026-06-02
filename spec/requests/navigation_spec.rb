require "rails_helper"

RSpec.describe "Navigation", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:merchant_admin)  { create(:user, :merchant_admin, merchant_id: "merch_abc") }

  describe "root path" do
    it "redirects unauthenticated users to sign in" do
      get "/"
      expect(response).to redirect_to(new_user_session_path)
    end

    it "routes authenticated users to payments (no redirect loop)" do
      sign_in psp_admin
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payments")
    end
  end

  describe "primary navigation" do
    context "when signed in as a PSP role" do
      before { sign_in psp_admin }

      it "shows Payments and Shops links" do
        get payments_path
        expect(response.body).to include("Payments")
        expect(response.body).to include(shops_path)
      end

      it "shows a sign out control" do
        get payments_path
        expect(response.body).to include(destroy_user_session_path)
      end

      it "shows the signed-in user's email" do
        get payments_path
        expect(response.body).to include(psp_admin.email)
      end
    end

    context "when signed in as a merchant role" do
      before { sign_in merchant_admin }

      it "shows the Payments link" do
        get payments_path
        expect(response.body).to include(payments_path)
      end

      it "shows Shops for merchant_admin" do
        get payments_path
        expect(response.body).to include(shops_path)
      end
    end

    context "when signed out" do
      it "does not render the primary nav on the sign-in page" do
        get new_user_session_path
        expect(response.body).not_to include("data-testid=\"primary-nav\"")
      end
    end
  end
end
