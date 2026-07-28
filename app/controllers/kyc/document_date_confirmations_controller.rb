# frozen_string_literal: true

# Confirms or corrects a single extracted validity date on a KycDocument
# (MH-196). Every successful call appends a new Kyc::DocumentDateConfirmation
# audit row via Kyc::DocumentValidity::DateConfirmationService — it never
# updates a prior confirmation.
#
# POST /kyc/document_date_confirmations
class Kyc::DocumentDateConfirmationsController < ApplicationController
  include ActionView::RecordIdentifier

  expose(:document) { KycDocument.find(params[:kyc_document_id]) }

  def create
    authorize document, :confirm_dates?

    result = Kyc::DocumentValidity::DateConfirmationService.call(
      document: document,
      date_role: params[:date_role],
      confirmed_value: params[:confirmed_value],
      reason: params[:reason],
      actor: current_user
    )

    status = result.success? ? :ok : :unprocessable_entity

    respond_to do |format|
      # MH-200: replaces the same dom_id(document) target that
      # Kyc::DocumentsController#update and KycDocumentBroadcaster already
      # use to re-render the whole kyc/documents/kyc_document partial —
      # confirming/correcting a date can change the document's validity
      # outcome, replacement progress, and confirmation history, none of
      # which lived inside the narrower per-role date_confirmation target
      # this used to replace. errored_role/errors thread validation
      # failures back to just the role that was submitted.
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(document),
          partial: "kyc/documents/kyc_document",
          locals: { document: document, errored_role: params[:date_role], errors: result.errors }
        ), status: status
      end
      format.html do
        if result.success?
          redirect_back fallback_location: applicant_path(document.applicant),
                         notice: t("kyc.documents.date_confirmations.success")
        else
          redirect_back fallback_location: applicant_path(document.applicant),
                         alert: result.errors.full_messages.to_sentence
        end
      end
    end
  end
end
