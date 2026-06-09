# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Team", type: :request do
  let_it_be(:merchant_admin)  { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:other_admin)     { create(:user, :merchant_admin, merchant_id: "merch_xyz") }
  let_it_be(:team_member)     { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  describe "GET /team" do
    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 200 and lists team members" do
        get team_index_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(team_member.email)
      end

      it "does not list users from other merchants" do
        get team_index_path
        expect(response.body).not_to include(other_admin.email)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get team_index_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get team_index_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /team/new" do
    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 200" do
        get new_team_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get new_team_path
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /team" do
    before { sign_in merchant_admin }

    context "with valid params" do
      it "creates a user and redirects to team index" do
        expect {
          post team_index_path, params: { user: { email: "new@merch.com", role: "merchant_viewer" } }
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(team_index_path)
        expect(User.last.merchant_id).to eq("merch_abc")
      end
    end

    context "with invalid email" do
      it "re-renders new with 422" do
        post team_index_path, params: { user: { email: "not-an-email", role: "merchant_viewer" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when attempting to invite a psp role" do
      it "returns an error" do
        post team_index_path, params: { user: { email: "hack@example.com", role: "psp_admin" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        post team_index_path, params: { user: { email: "x@x.com", role: "merchant_viewer" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /team/:id" do
    before { sign_in merchant_admin }

    it "deactivates the team member and redirects" do
      delete team_path(team_member)
      expect(response).to redirect_to(team_index_path)
      expect(team_member.reload.deactivated_at).not_to be_nil
    end

    it "returns 403 when trying to deactivate self" do
      delete team_path(merchant_admin)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 when trying to deactivate a user from another merchant" do
      delete team_path(other_admin)
      expect(response).to have_http_status(:not_found)
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        delete team_path(team_member)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
