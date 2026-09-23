# frozen_string_literal: true

# Resolves a document's registry date-of-birth mismatch (MH-303).
#
# POST /kyc/principal_match_overrides
class Kyc::PrincipalMatchOverridesController < ApplicationController
  include ActionView::RecordIdentifier
  include KycDocumentBroadcaster

  expose(:document) { KycDocument.find(params[:kyc_document_id]) }

  def create
    authorize document, :resolve_dob_mismatch?

    result = Kyc::PrincipalMatchOverrideService.call(
      document: document,
      resolution: params[:resolution],
      reason: params[:reason],
      actor: current_user
    )

    status = result.success? ? :ok : :unprocessable_content
    broadcast_document(document) if result.success?

    respond_to do |format|
      format.turbo_stream do
        # MH-322: "#{dom_id(document)}_content" — see kyc/documents/_kyc_document.html.erb.
        render turbo_stream: turbo_stream.replace(
          "#{dom_id(document)}_content",
          partial: "kyc/documents/kyc_document",
          locals: { document: document, override_errors: result.errors }
        ), status: status
      end
      format.html do
        if result.success?
          redirect_back fallback_location: applicant_path(document.applicant),
                         notice: t("kyc.documents.principal_match_overrides.success")
        else
          redirect_back fallback_location: applicant_path(document.applicant),
                         alert: result.errors.full_messages.to_sentence
        end
      end
    end
  end
end
