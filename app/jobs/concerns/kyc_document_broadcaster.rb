# frozen_string_literal: true

module KycDocumentBroadcaster
  extend ActiveSupport::Concern

  private

  def broadcast_document(document)
    Turbo::StreamsChannel.broadcast_replace_to(
      "applicant_#{document.applicant_id}_documents",
      target: "kyc_document_#{document.id}",
      partial: "kyc/documents/kyc_document",
      locals: { document: document }
    )
  end
end
