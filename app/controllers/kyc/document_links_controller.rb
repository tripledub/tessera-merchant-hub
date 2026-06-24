# frozen_string_literal: true

# Manages the link between a KycDocument and a KycPrincipal.
#
# PATCH  /kyc_document_links/:id  — confirm the automated link
# DELETE /kyc_document_links/:id  — reject the link (unlink document from principal)
class Kyc::DocumentLinksController < ApplicationController
  include ActionView::RecordIdentifier
  include KycDocumentBroadcaster

  expose(:document) { KycDocument.find(params[:id]) }

  def update
    authorize document, :confirm_link?
    document.kyc_principal&.confirmed!
    document.update!(match_method: "exact", match_confidence: 1.0)
    broadcast_document(document)
    head :ok
  end

  def destroy
    authorize document, :reject_link?
    document.update!(kyc_principal: nil, match_method: nil, match_confidence: nil)
    broadcast_document(document)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(document)) }
      format.html { redirect_back fallback_location: applicant_path(document.applicant) }
    end
  end
end
