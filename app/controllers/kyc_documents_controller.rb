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

    files.each do |file|
      doc = KycDocument.new(applicant: applicant, status: :pending)
      doc.file.attach(file)
      if doc.save
        ProcessKycDocumentJob.perform_later(doc.id)
      end
    end

    redirect_to applicant_path(applicant), notice: t("flash.kyc_documents.upload_success", count: files.size)
  end
end
