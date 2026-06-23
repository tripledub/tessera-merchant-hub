# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::ValidationWarnings", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:document)  { create(:kyc_document, applicant: applicant) }
  let_it_be(:warning)   { create(:kyc_validation_warning, applicant: applicant, kyc_document: document, acknowledged: false) }

  describe "PATCH /kyc/validation_warnings/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "acknowledges the warning" do
        patch kyc_validation_warning_path(warning)
        expect(warning.reload.acknowledged).to be true
      end

      it "returns turbo_stream response when requested" do
        patch kyc_validation_warning_path(warning), headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "redirects for HTML requests" do
        patch kyc_validation_warning_path(warning), headers: { "HTTP_REFERER" => applicant_path(applicant) }
        expect(response).to redirect_to(applicant_path(applicant))
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        patch kyc_validation_warning_path(warning)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        patch kyc_validation_warning_path(warning)
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
