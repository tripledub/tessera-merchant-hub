# frozen_string_literal: true

class Kyc::ExtractionRunsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) }

  def create
    authorize applicant, :run_extraction?
    docs = applicant.kyc_documents.where(classification_status: :confirmed, status: :pending)
    docs.each { |doc| ExtractKycDocumentJob.perform_later(doc.id) }
    redirect_to applicant_path(applicant),
      notice: t("flash.kyc_documents.extraction_started", count: docs.size)
  end
end
