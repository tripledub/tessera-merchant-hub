# frozen_string_literal: true

class Kyc::ExtractionRunsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) }

  def create
    authorize applicant, :run_extraction?
    docs = applicant.kyc_documents.where(classification_status: :confirmed, status: :pending)
    docs.each { |doc| ExtractKycDocumentJob.perform_later(doc.id) }

    respond_to do |format|
      format.turbo_stream do
        total = applicant.kyc_documents.where(classification_status: :confirmed).count
        render turbo_stream: [
          turbo_stream.append(
            "toast-container",
            partial: "shared/toast",
            locals: { message: t("flash.kyc_documents.extraction_started", count: docs.size), type: :info }
          ),
          turbo_stream.update(
            "extraction-progress-container",
            partial: "kyc/documents/extraction_progress",
            locals: { total: total }
          )
        ]
      end
      format.html do
        redirect_to applicant_path(applicant),
          notice: t("flash.kyc_documents.extraction_started", count: docs.size)
      end
    end
  end
end
