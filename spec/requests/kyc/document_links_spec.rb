# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::DocumentLinks", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:psp_support)     { create(:user, :psp_support) }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer) }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:principal) { create(:kyc_principal, applicant: applicant, name: "Jane Doe", status: :unconfirmed) }

  describe "PATCH /kyc/document_links/:id" do
    let!(:document) do
      create(:kyc_document, applicant: applicant, kyc_principal: principal,
             match_method: "fuzzy", match_confidence: 0.95)
    end

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "confirms the principal and updates match to exact" do
        patch kyc_document_link_path(document)

        expect(response).to have_http_status(:ok)
        expect(document.reload.match_method).to eq("exact")
        expect(document.reload.match_confidence).to eq(1.0)
        expect(principal.reload.status).to eq("confirmed")
      end

      it "broadcasts a turbo stream update" do
        patch kyc_document_link_path(document)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        patch kyc_document_link_path(document)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        patch kyc_document_link_path(document)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "DELETE /kyc/document_links/:id" do
    let!(:document) do
      create(:kyc_document, applicant: applicant, kyc_principal: principal,
             match_method: "exact", match_confidence: 1.0)
    end

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "unlinks the document from the principal" do
        delete kyc_document_link_path(document),
               headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        document.reload
        expect(document.kyc_principal).to be_nil
        expect(document.match_method).to be_nil
        expect(document.match_confidence).to be_nil
      end

      it "returns a turbo stream remove action" do
        delete kyc_document_link_path(document),
               headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("turbo-stream")
      end

      it "redirects back for HTML requests" do
        delete kyc_document_link_path(document),
               headers: { "HTTP_REFERER" => applicant_path(applicant) }

        expect(response).to redirect_to(applicant_path(applicant))
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        delete kyc_document_link_path(document)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        delete kyc_document_link_path(document)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
