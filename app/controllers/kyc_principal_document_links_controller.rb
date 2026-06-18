# frozen_string_literal: true

class KycPrincipalDocumentLinksController < ApplicationController
  expose(:kyc_principal) { KycPrincipal.find(params[:kyc_principal_id]) }

  def new
    authorize kyc_principal, :show?
    @unlinked_documents = kyc_principal.applicant.kyc_documents.where(kyc_principal_id: nil).order(created_at: :desc)
  end

  def create
    authorize kyc_principal, :update?
    @document = kyc_principal.applicant.kyc_documents.find(params[:document_id])
    @document.update!(kyc_principal: kyc_principal, match_method: "exact", match_confidence: 1.0)
    respond_to do |format|
      format.turbo_stream
    end
  end
end
