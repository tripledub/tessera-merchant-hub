# frozen_string_literal: true

module KycDocumentBroadcaster
  extend ActiveSupport::Concern

  private

  # Broadcasts only the metadata sub-fragment, not the full
  # kyc/documents/kyc_document partial. That partial also renders the
  # date-confirmation form, gated on a Pundit policy check — but a Turbo
  # broadcast renders via ActionController::Renderer, which has no
  # Warden::Proxy, so there is no real "current viewer" to authorize
  # against. Broadcasting the full partial would either raise
  # Devise::MissingWarden (the bug this fixed) or, with authorization
  # short-circuited to false, silently blank out the confirmation form
  # for every connected viewer regardless of their actual permissions —
  # including an admin who already had it open. Scoping the broadcast to
  # the user-independent metadata leaves whatever the confirmation
  # section already rendered (via a real, per-viewer request) untouched.
  def broadcast_document(document)
    Turbo::StreamsChannel.broadcast_replace_to(
      "applicant_#{document.applicant_id}_documents",
      target: "kyc_document_#{document.id}_metadata",
      partial: "kyc/documents/kyc_document_metadata",
      locals: { document: document }
    )
  end
end
