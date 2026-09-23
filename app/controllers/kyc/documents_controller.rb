# frozen_string_literal: true

class Kyc::DocumentsController < ApplicationController
  include ActionView::RecordIdentifier
  include KycDocumentBroadcaster

  expose(:applicant) { Applicant.find(params[:applicant_id]) }
  expose(:document) { KycDocument.find(params[:id]) }

  def create
    authorize KycDocument, :create?
    files = params[:kyc_document]&.fetch(:files, [])&.compact_blank

    if files.blank?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "toast-container",
            partial: "shared/toast",
            locals: { message: t("flash.kyc_documents.no_files"), type: :error }
          )
        end
        format.html { redirect_to applicant_path(applicant), alert: t("flash.kyc_documents.no_files") }
      end
      return
    end

    had_no_documents = applicant.kyc_documents.none?
    saved_documents = []
    skipped = 0

    files.each do |file|
      doc = KycDocument.new(applicant: applicant, status: :pending)
      # Save first so doc.id exists before Active Storage creates the attachment
      # record. Attaching before save causes record_id = NULL when the Async job
      # adapter processes the first job concurrently with subsequent iterations.
      next unless doc.save(validate: false)

      begin
        doc.file.attach(file)
      rescue ArgumentError, ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature => e
        doc.destroy
        Rails.logger.warn("Kyc::DocumentsController: skipping unattachable file — #{e.message}")
        skipped += 1
        next
      end

      unless doc.file.attached? && doc.valid?
        doc.destroy
        skipped += 1
        next
      end

      ClassifyKycDocumentJob.perform_later(doc.id)
      saved_documents << doc
    end

    saved = saved_documents.size
    message = saved.zero? ? t("flash.kyc_documents.no_files") : t("flash.kyc_documents.upload_success", count: saved)
    type = saved.zero? ? :error : :success

    respond_to do |format|
      format.turbo_stream do
        streams = []
        if saved_documents.any?
          streams << turbo_stream.remove("kyc-documents-empty") if had_no_documents
          # MH-302: a freshly-uploaded document always starts unclassified, so
          # it always belongs in the Unconfirmed Files panel.
          streams.concat(saved_documents.map { |doc|
            turbo_stream.append("documents-panel-unconfirmed-list", partial: "kyc/documents/kyc_document_row", locals: { document: doc })
          })
        end
        streams << turbo_stream.append("toast-container", partial: "shared/toast", locals: { message: message, type: type })
        if skipped.positive?
          streams << turbo_stream.append(
            "toast-container",
            partial: "shared/toast",
            locals: { message: t("flash.kyc_documents.skipped_invalid", count: skipped), type: :warning }
          )
        end
        render turbo_stream: streams
      end
      format.html do
        redirect_to applicant_path(applicant), saved.zero? ? { alert: message } : { notice: message }
      end
    end
  end

  def destroy
    authorize document
    document.file.purge_later
    document.destroy!
    Turbo::StreamsChannel.broadcast_remove_to(
      "applicant_#{document.applicant_id}_documents",
      target: "kyc_document_#{document.id}"
    )
    head :ok
  end

  def update
    authorize document
    document.with_lock do
      attrs = {}
      doc_type = params.dig(:kyc_document, :document_type)

      if doc_type.present? && document.processing_statement.nil? && document.selectable_document_types.include?(doc_type)
        attrs[:document_type] = doc_type
      end

      classification = params.dig(:kyc_document, :classification_status)
      if classification.present? && KycDocument.classification_statuses.key?(classification)
        attrs[:classification_status] = classification
        attrs[:classification_method] = document.classification_method || "manual" if classification == "confirmed"
      end

      if document.processing_statement? && document.classification_method == "spreadsheet_content_type" &&
          attrs[:document_type].present? && %w[processing_statement other].exclude?(attrs[:document_type])
        attrs[:status] = :pending
      end

      document.update!(attrs) if attrs.any?
      if document.processing_statement? && document.classification_confirmed?
        ProcessingStatements::RouteFromKycDocument.call(document)
      end
    end
    broadcast_document(document)

    respond_to do |format|
      format.turbo_stream do
        docs = document.applicant.kyc_documents
        render turbo_stream: [
          # MH-322: "#{dom_id(document)}_content", not dom_id(document) — see the
          # comment on kyc/documents/_kyc_document.html.erb's outer div.
          turbo_stream.replace(
            "#{dom_id(document)}_content",
            partial: "kyc/documents/kyc_document",
            locals: { document: document }
          ),
          turbo_stream.replace(
            "classification-counter",
            partial: "kyc/documents/classification_counter",
            locals: {
              confirmed_count: docs.where(classification_status: :confirmed).count,
              total_count: docs.count
            }
          ),
          turbo_stream.replace(
            "extraction-controls",
            partial: "kyc/documents/extraction_button",
            locals: { applicant: document.applicant }
          )
        ]
      end
      format.html { redirect_to applicant_path(document.applicant) }
    end
  end

  def comment_status
    authorize document, :update_comment_status?

    status = params[:comment_status]
    document.update!(comment_status: status) if KycDocument.comment_statuses.key?(status)
    broadcast_document(document)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # MH-322: "#{dom_id(document)}_content" — see kyc/documents/_kyc_document.html.erb.
          turbo_stream.replace(
            "#{dom_id(document)}_content",
            partial: "kyc/documents/kyc_document",
            locals: { document: document }
          ),
          turbo_stream.update(
            "document-comments-modal",
            partial: "kyc/document_comments/modal_content",
            locals: { kyc_document: document, comment_errors: nil }
          )
        ]
      end
      format.html { redirect_to applicant_path(document.applicant) }
    end
  end

  def retry
    authorize document
    document.update!(
      status: :pending, result: nil,
      document_type: nil, classification_status: :unclassified,
      classification_confidence: nil, classification_method: nil,
      kyc_principal: nil, match_method: nil, match_confidence: nil
    )
    ClassifyKycDocumentJob.perform_later(document.id)
    broadcast_document(document)
    head :ok
  end

  # MH-322: opens the date-confirmation modal from the row's overflow menu.
  def date_confirmation_modal
    authorize document, :confirm_dates?
    render partial: "kyc/document_date_confirmations/modal", locals: { document: document }, layout: false
  end
end
