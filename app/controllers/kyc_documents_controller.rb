# frozen_string_literal: true

class KycDocumentsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) }

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

      doc.file.attach(file)
      next unless doc.file.attached? && doc.valid?

      ProcessKycDocumentJob.perform_later(doc.id)
      saved += 1
    end

    if saved.zero?
      redirect_to applicant_path(applicant), alert: t("flash.kyc_documents.no_files")
    else
      redirect_to applicant_path(applicant), notice: t("flash.kyc_documents.upload_success", count: saved)
    end
  end
end
