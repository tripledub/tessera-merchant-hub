# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::PrincipalMatchOverrides", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin) }

  let_it_be(:applicant) { create(:applicant) }

  let!(:registry_principal) do
    create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
      date_of_birth_month: 3, date_of_birth_year: 1985)
  end

  let!(:document) do
    create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
      dob_mismatch_kyc_principal: registry_principal,
      extracted_data: { "full_name" => "Riley Sample", "date_of_birth" => "1990-06-02" })
  end

  describe "POST /kyc/principal_match_overrides" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "links the document anyway with a reason" do
        post kyc_principal_match_overrides_path,
             params: { kyc_document_id: document.id, resolution: "link_anyway", reason: "Same person" }

        expect(response).to have_http_status(:ok).or have_http_status(:redirect)
        expect(document.reload.kyc_principal).to eq(registry_principal)
        expect(Kyc::PrincipalMatchOverride.last).to be_link_anyway
      end

      it "creates a different person with a reason" do
        expect {
          post kyc_principal_match_overrides_path,
               params: { kyc_document_id: document.id, resolution: "different_person", reason: "Not the same person" }
        }.to change(KycPrincipal, :count).by(1)

        expect(document.reload.kyc_principal).not_to eq(registry_principal)
      end

      it "rejects a resolution with no reason" do
        expect {
          post kyc_principal_match_overrides_path,
               params: { kyc_document_id: document.id, resolution: "link_anyway", reason: "" }
        }.not_to change(Kyc::PrincipalMatchOverride, :count)

        expect(response).to have_http_status(:unprocessable_content).or have_http_status(:redirect)
        expect(document.reload.kyc_principal).to be_nil
      end

      it "returns a turbo stream response for turbo_stream format" do
        post kyc_principal_match_overrides_path,
             params: { kyc_document_id: document.id, resolution: "link_anyway", reason: "Same person" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post kyc_principal_match_overrides_path,
             params: { kyc_document_id: document.id, resolution: "link_anyway", reason: "Same person" }

        expect(response).to have_http_status(:forbidden)
        expect(document.reload.kyc_principal).to be_nil
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        post kyc_principal_match_overrides_path,
             params: { kyc_document_id: document.id, resolution: "link_anyway", reason: "Same person" }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        post kyc_principal_match_overrides_path,
             params: { kyc_document_id: document.id, resolution: "link_anyway", reason: "Same person" }

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
