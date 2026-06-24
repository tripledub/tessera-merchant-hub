# frozen_string_literal: true

module Kyc
  class EntityDocumentLinksController < ApplicationController
    include ActionView::RecordIdentifier

    expose(:corporate_entity) { Kyc::CorporateEntity.find(params[:corporate_entity_id]) }

    def new
      authorize corporate_entity.applicant, :show?
      @unlinked_documents = corporate_entity.applicant.kyc_documents
        .where(corporate_entity_id: nil)
        .order(created_at: :desc)
    end

    def create
      authorize corporate_entity.applicant, :show?
      @document = corporate_entity.applicant.kyc_documents.find(params[:document_id])
      @document.update!(corporate_entity: corporate_entity)
      respond_to do |format|
        format.turbo_stream
      end
    end

    def destroy
      authorize corporate_entity.applicant, :show?
      @document = corporate_entity.linked_documents.find(params[:id])
      @document.update!(corporate_entity: nil)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@document, :entity_doc)) }
        format.html { redirect_back fallback_location: kyc_corporate_entity_path(corporate_entity) }
      end
    end
  end
end
