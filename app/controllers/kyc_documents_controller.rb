# frozen_string_literal: true

class KycDocumentsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) }
  expose(:document)  { KycDocument.find(params[:id]) }

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

      ProcessKycDocumentJob.perform_later(doc.id)
      saved += 1
    end

    if saved.zero?
      redirect_to applicant_path(applicant), alert: t("flash.kyc_documents.no_files")
    else
      redirect_to applicant_path(applicant), notice: t("flash.kyc_documents.upload_success", count: saved)
    end
  end

  def confirm_match
    authorize document, :confirm_match?
    document.kyc_principal&.confirmed!
    document.update!(match_method: "exact", match_confidence: 1.0)
    broadcast_document(document)
    head :ok
  end

  def reject_match
    authorize document, :reject_match?
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
