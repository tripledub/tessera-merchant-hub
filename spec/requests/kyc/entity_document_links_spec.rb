# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::EntityDocumentLinks", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer) }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:source_doc) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let_it_be(:entity) do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_doc, name: "Acme Holdings Ltd")
  end

  let_it_be(:unlinked_document) { create(:kyc_document, applicant: applicant, document_type: :certificate_of_incorporation) }

  before { sign_in psp_admin }

  describe "GET /kyc/corporate_entities/:corporate_entity_id/entity_document_links/new" do
    it "returns 200 and shows unlinked documents" do
      get new_kyc_corporate_entity_entity_document_link_path(entity)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Link documents to entity")
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get new_kyc_corporate_entity_entity_document_link_path(entity)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /kyc/corporate_entities/:corporate_entity_id/entity_document_links" do
    it "links the document to the entity" do
      post kyc_corporate_entity_entity_document_links_path(entity),
           params: { document_id: unlinked_document.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(unlinked_document.reload.corporate_entity).to eq(entity)
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        post kyc_corporate_entity_entity_document_links_path(entity),
             params: { document_id: unlinked_document.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /kyc/corporate_entities/:corporate_entity_id/entity_document_links/:id" do
    let!(:linked_document) do
      create(:kyc_document, applicant: applicant, document_type: :articles_of_association,
             corporate_entity: entity)
    end

    it "unlinks the document from the entity" do
      delete kyc_corporate_entity_entity_document_link_path(entity, linked_document),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(linked_document.reload.corporate_entity).to be_nil
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        delete kyc_corporate_entity_entity_document_link_path(entity, linked_document)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
