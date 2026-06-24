# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::PrincipalDocumentLinks", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:psp_support)     { create(:user, :psp_support) }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer) }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:principal) { create(:kyc_principal, applicant: applicant, name: "John Smith") }
  let_it_be(:unlinked_doc) { create(:kyc_document, applicant: applicant, kyc_principal: nil) }

  describe "GET /kyc/principals/:principal_id/document_links/new" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get new_kyc_principal_document_links_path(principal)

        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200 (psp_support can view principals)" do
        get new_kyc_principal_document_links_path(principal)

        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get new_kyc_principal_document_links_path(principal)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get new_kyc_principal_document_links_path(principal)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "POST /kyc/principals/:principal_id/document_links" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "links the document to the principal" do
        post kyc_principal_document_links_path(principal),
             params: { document_id: unlinked_doc.id },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        unlinked_doc.reload
        expect(unlinked_doc.kyc_principal).to eq(principal)
        expect(unlinked_doc.match_method).to eq("exact")
        expect(unlinked_doc.match_confidence).to eq(1.0)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post kyc_principal_document_links_path(principal),
             params: { document_id: unlinked_doc.id }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        post kyc_principal_document_links_path(principal),
             params: { document_id: unlinked_doc.id }

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
