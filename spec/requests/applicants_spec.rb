# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Applicants", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin) }

  let_it_be(:applicant_a) { create(:applicant, name: "Acme Corp") }
  let_it_be(:applicant_b) { create(:applicant, name: "Beta Ltd") }

  describe "GET /applicants" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 and lists applicants" do
        get applicants_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Corp")
        expect(response.body).to include("Beta Ltd")
      end

      it "filters by name" do
        get applicants_path, params: { q: "Acme" }
        expect(response.body).to include("Acme Corp")
        expect(response.body).not_to include("Beta Ltd")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200" do
        get applicants_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get applicants_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get applicants_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /applicants/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get applicant_path(applicant_a)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Corp")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200" do
        get applicant_path(applicant_a)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get applicant_path(applicant_a)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /applicants/new" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get new_applicant_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get new_applicant_path
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "creates applicant and redirects to show" do
        post applicants_path, params: {
          applicant: { name: "New Corp", company_name: "New Corp Ltd", contact_email: "info@new.com" }
        }
        created = Applicant.find_by!(name: "New Corp")
        expect(response).to redirect_to(applicant_path(created))
      end

      it "re-renders new with 422 on invalid params" do
        post applicants_path, params: { applicant: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post applicants_path, params: { applicant: { name: "X" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /applicants/:id/edit" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get edit_applicant_path(applicant_a)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get edit_applicant_path(applicant_a)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /applicants/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "updates and redirects to show" do
        patch applicant_path(applicant_a), params: {
          applicant: { contact_email: "updated@acme.com" }
        }
        expect(response).to redirect_to(applicant_path(applicant_a))
        expect(applicant_a.reload.contact_email).to eq("updated@acme.com")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        patch applicant_path(applicant_a), params: { applicant: { name: "X" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
