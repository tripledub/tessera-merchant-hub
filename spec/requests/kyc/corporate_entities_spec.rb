# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::CorporateEntities", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer) }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:document)  { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let_it_be(:entity)    { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, name: "Test Holdings Ltd") }

  describe "GET /kyc/corporate_entities/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get kyc_corporate_entity_path(entity)
        expect(response).to have_http_status(:ok)
      end

      it "renders the entity name" do
        get kyc_corporate_entity_path(entity)
        expect(response.body).to include("Test Holdings Ltd")
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get kyc_corporate_entity_path(entity)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
