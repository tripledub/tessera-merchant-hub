# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::CrossReferences", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:psp_support)     { create(:user, :psp_support) }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer) }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:source_doc) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let_it_be(:entity) do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_doc, name: "Acme Holdings Ltd")
  end

  describe "POST /kyc/corporate_entities/:corporate_entity_id/cross_reference" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "calls CrossReferenceService and redirects" do
        allow(Kyc::CrossReferenceService).to receive(:call)
          .and_return(Kyc::CrossReferenceService::Result.new(inference_errors: []))

        post kyc_corporate_entity_cross_reference_path(entity)

        expect(Kyc::CrossReferenceService).to have_received(:call).with(entity)
        expect(response).to redirect_to(kyc_corporate_entity_path(entity))
      end

      it "returns a turbo_stream response when requested" do
        allow(Kyc::CrossReferenceService).to receive(:call)
          .and_return(Kyc::CrossReferenceService::Result.new(inference_errors: []))

        post kyc_corporate_entity_cross_reference_path(entity),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("Cross-reference complete")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "allows access (psp_support can view applicants)" do
        allow(Kyc::CrossReferenceService).to receive(:call)
          .and_return(Kyc::CrossReferenceService::Result.new(inference_errors: []))

        post kyc_corporate_entity_cross_reference_path(entity)

        expect(response).to redirect_to(kyc_corporate_entity_path(entity))
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        post kyc_corporate_entity_cross_reference_path(entity)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        post kyc_corporate_entity_cross_reference_path(entity)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
