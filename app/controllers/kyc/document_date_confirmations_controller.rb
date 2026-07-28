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

    presenter = Kyc::DocumentDateConfirmationPresenter.new(document, view_context)
    status = result.success? ? :ok : :unprocessable_entity

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          date_confirmation_dom_id(document, params[:date_role]),
          partial: "kyc/document_date_confirmations/date_confirmation",
          locals: { document: document, date_role: params[:date_role], presenter: presenter, errors: result.errors }
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

  private

  def date_confirmation_dom_id(document, date_role)
    "date_confirmation_#{dom_id(document)}_#{date_role}"
  end
end
