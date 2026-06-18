# frozen_string_literal: true

# Manages the link between a KycDocument and a KycPrincipal.
#
# PATCH  /kyc_document_links/:id  — confirm the automated link
# DELETE /kyc_document_links/:id  — reject the link (unlink document from principal)
class KycDocumentLinksController < ApplicationController
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
    head :ok
  end

  private

  def broadcast_document(doc)
    Turbo::StreamsChannel.broadcast_replace_to(
      "applicant_#{doc.applicant_id}_documents",
      target: "kyc_document_#{doc.id}",
      partial: "kyc_documents/kyc_document",
      locals: { document: doc }
    )
  end
end
