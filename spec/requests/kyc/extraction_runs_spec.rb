# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ExtractionRuns", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant) }

  describe "POST /applicants/:applicant_id/extraction_run" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "enqueues extraction for confirmed documents and responds with toast" do
        doc = create(:kyc_document, applicant: applicant, document_type: :passport,
          classification_status: :confirmed, status: :pending)

        expect {
          post applicant_kyc_extraction_run_path(applicant),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
        }.to have_enqueued_job(ExtractKycDocumentJob).with(doc.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("turbo-stream")
      end

      it "falls back to redirect for non-Turbo requests" do
        create(:kyc_document, applicant: applicant, document_type: :passport,
          classification_status: :confirmed, status: :pending)

        post applicant_kyc_extraction_run_path(applicant)
        expect(response).to redirect_to(applicant_path(applicant))
      end

      it "does not enqueue extraction for unconfirmed documents" do
        create(:kyc_document, applicant: applicant, document_type: :passport,
          classification_status: :auto_classified, status: :pending)

        expect {
          post applicant_kyc_extraction_run_path(applicant)
        }.not_to have_enqueued_job(ExtractKycDocumentJob)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post applicant_kyc_extraction_run_path(applicant)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
