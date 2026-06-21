# frozen_string_literal: true

require "rails_helper"

RSpec.describe "KycDocuments", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant) }

  describe "POST /applicants/:applicant_id/kyc_documents" do
    let(:file) { fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.pdf"), "application/pdf") }

    before { create_fixture_file }

    def create_fixture_file
      dir = Rails.root.join("spec/fixtures/files")
      FileUtils.mkdir_p(dir)
      File.write(dir.join("sample.pdf"), "%PDF-1.4 fake content")
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "enqueues a ClassifyKycDocumentJob and redirects to applicant" do
        expect {
          post applicant_kyc_documents_path(applicant), params: {
            kyc_document: { files: [ file ] }
          }
        }.to have_enqueued_job(ClassifyKycDocumentJob)
        expect(response).to redirect_to(applicant_path(applicant))
      end

      it "redirects with alert when no files provided" do
        post applicant_kyc_documents_path(applicant), params: { kyc_document: { files: [] } }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(flash[:alert]).to be_present
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post applicant_kyc_documents_path(applicant), params: {
          kyc_document: { files: [ file ] }
        }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        post applicant_kyc_documents_path(applicant), params: { kyc_document: { files: [] } }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "DELETE /kyc_documents/:id" do
    let_it_be(:document) { create(:kyc_document, applicant: applicant) }

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
      end

      it "destroys the document and returns 200" do
        delete kyc_document_path(document)
        expect(response).to have_http_status(:ok)
        expect(KycDocument.find_by(id: document.id)).to be_nil
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        delete kyc_document_path(document)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /kyc_documents/:id/confirm_classification" do
    let_it_be(:document) do
      create(:kyc_document, applicant: applicant, document_type: :passport, classification_status: :auto_classified)
    end

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "confirms classification without triggering extraction" do
        patch confirm_classification_kyc_document_path(document)
        expect(response).to have_http_status(:ok)
        expect(document.reload.classification_status).to eq("confirmed")
        expect(ExtractKycDocumentJob).not_to have_been_enqueued
      end

      it "allows overriding the document type" do
        patch confirm_classification_kyc_document_path(document), params: { document_type: "utility_bill" }
        expect(document.reload.document_type).to eq("utility_bill")
        expect(document.classification_status).to eq("confirmed")
      end

      it "ignores invalid document types" do
        patch confirm_classification_kyc_document_path(document), params: { document_type: "invalid_type" }
        expect(document.reload.document_type).to eq("passport")
        expect(document.classification_status).to eq("confirmed")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        patch confirm_classification_kyc_document_path(document)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /kyc_documents/:id/retry" do
    let_it_be(:document) { create(:kyc_document, applicant: applicant, status: :error) }

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "resets the document and enqueues ClassifyKycDocumentJob" do
        expect {
          post retry_kyc_document_path(document)
        }.to have_enqueued_job(ClassifyKycDocumentJob).with(document.id)
        expect(response).to have_http_status(:ok)
        expect(document.reload.status).to eq("pending")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post retry_kyc_document_path(document)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
