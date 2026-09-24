# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::DocumentReviews", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant) }

  describe "POST /kyc/documents/:document_id/review (MH-327)" do
    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "completes an other-typed, confirmed document" do
        document = create(:kyc_document, applicant: applicant, document_type: :other,
          classification_status: :confirmed, status: :pending)

        post kyc_document_review_path(document)

        expect(response).to have_http_status(:ok)
        expect(document.reload.status).to eq("complete")
      end

      it "rejects a document that isn't other-typed" do
        document = create(:kyc_document, applicant: applicant, document_type: :passport,
          classification_status: :confirmed, status: :pending)

        post kyc_document_review_path(document)

        expect(response).to have_http_status(:unprocessable_content)
        expect(document.reload.status).to eq("pending")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        document = create(:kyc_document, applicant: applicant, document_type: :other,
          classification_status: :confirmed, status: :pending)

        post kyc_document_review_path(document)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
