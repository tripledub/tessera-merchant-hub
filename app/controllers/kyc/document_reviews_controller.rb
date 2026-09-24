# frozen_string_literal: true

# MH-327: for a document type with no extraction handler (currently just
# `other`), ExtractKycDocumentJob never runs, so status never advances past
# :pending on its own — a reviewer marking it reviewed is the only way it can
# ever reach the Processed panel.
class Kyc::DocumentReviewsController < ApplicationController
  include KycDocumentBroadcaster

  expose(:document) { KycDocument.find(params[:document_id]) }

  def create
    authorize document, :mark_reviewed?
    return head :unprocessable_content unless document.other?

    document.update!(status: :complete)
    broadcast_document(document)
    head :ok
  end
end
