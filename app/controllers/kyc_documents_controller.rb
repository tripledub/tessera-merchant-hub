# frozen_string_literal: true

class KycDocumentsController < ApplicationController
  include ActionView::RecordIdentifier

  expose(:applicant) { Applicant.find(params[:applicant_id]) }
  expose(:document) { KycDocument.find(params[:id]) }

  def create
    authorize KycDocument, :create?
    files = params[:kyc_document]&.fetch(:files, [])&.compact_blank

    if files.blank?
      redirect_to applicant_path(applicant), alert: t("flash.kyc_documents.no_files")
      return
    end

    saved = 0
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
        Rails.logger.warn("KycDocumentsController: skipping unattachable file — #{e.message}")
        next
      end

      unless doc.file.attached? && doc.valid?
        doc.destroy
        next
      end

      ClassifyKycDocumentJob.perform_later(doc.id)
      saved += 1
    end

    if saved.zero?
      redirect_to applicant_path(applicant), alert: t("flash.kyc_documents.no_files")
    else
      redirect_to applicant_path(applicant), notice: t("flash.kyc_documents.upload_success", count: saved)
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
    attrs = {}
    doc_type = params.dig(:kyc_document, :document_type)

    if doc_type.present? && KycDocument.document_types.key?(doc_type)
      attrs[:document_type] = doc_type
    end

    classification = params.dig(:kyc_document, :classification_status)
    if classification.present? && KycDocument.classification_statuses.key?(classification)
      attrs[:classification_status] = classification
      attrs[:classification_method] = document.classification_method || "manual" if classification == "confirmed"
    end

    document.update!(attrs) if attrs.any?
    broadcast_document(document)

    respond_to do |format|
      format.turbo_stream do
        docs = document.applicant.kyc_documents
        render turbo_stream: [
          turbo_stream.replace(
            dom_id(document),
            partial: "kyc_documents/kyc_document",
            locals: { document: document }
          ),
          turbo_stream.replace(
            "classification-counter",
            partial: "kyc_documents/classification_counter",
            locals: {
              confirmed_count: docs.where(classification_status: :confirmed).count,
              total_count: docs.count
            }
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
