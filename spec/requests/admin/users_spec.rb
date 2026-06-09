# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_user)  { create(:user, :merchant_viewer, merchant_id: "merch_abc") }
  let_it_be(:locked_user) do
    create(:user, :merchant_viewer, merchant_id: "merch_abc").tap do |u|
      u.lock_access!(send_instructions: false)
      u.update!(deactivated_at: Time.current)
    end
  end

  describe "GET /admin/users" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 and lists all users" do
        get admin_users_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(merchant_user.email)
      end

      it "filters by role" do
        get admin_users_path, params: { role: "psp_admin" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(psp_admin.email)
        expect(response.body).not_to include(merchant_user.email)
      end

      it "filters by merchant_id" do
        get admin_users_path, params: { merchant_id: "merch_abc" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(merchant_user.email)
        expect(response.body).not_to include(psp_support.email)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get admin_users_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get admin_users_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /admin/users/new" do
    before { sign_in psp_admin }

    it "returns 200" do
      get new_admin_user_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/users" do
    before { sign_in psp_admin }

    context "with valid psp_admin params" do
      it "creates a PSP user and redirects" do
        expect {
          post admin_users_path, params: { user: { email: "new-psp@tessera.test", role: "psp_support" } }
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(admin_users_path)
        expect(User.last.role).to eq("psp_support")
        expect(User.last.merchant_id).to be_nil
      end
    end

    context "with invalid email" do
      it "re-renders new with 422" do
        post admin_users_path, params: { user: { email: "bad", role: "psp_support" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        post admin_users_path, params: { user: { email: "x@x.com", role: "psp_admin" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /admin/users/:id/unlock" do
    before { sign_in psp_admin }

    it "clears locked_at and deactivated_at and redirects" do
      patch unlock_admin_user_path(locked_user)
      expect(response).to redirect_to(admin_users_path)
      locked_user.reload
      expect(locked_user.locked_at).to be_nil
      expect(locked_user.deactivated_at).to be_nil
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        patch unlock_admin_user_path(locked_user)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /admin/users/:id/update_role" do
    before { sign_in psp_admin }

    it "updates the role and redirects" do
      patch update_role_admin_user_path(merchant_user), params: { user: { role: "merchant_admin" } }
      expect(response).to redirect_to(admin_users_path)
      expect(merchant_user.reload.role).to eq("merchant_admin")
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        patch update_role_admin_user_path(merchant_user), params: { user: { role: "merchant_admin" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
