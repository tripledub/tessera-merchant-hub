# frozen_string_literal: true

module Kyc
  class ExtractionPresenter < BasePresenter
    presents :applicant

    def pending_count
      @pending_count ||= applicant.kyc_documents.where(classification_status: :confirmed, status: :pending).count
    end

    def pending?
      pending_count > 0
    end

    def pending_count_label
      t("applicants.show.documents.pending_extraction_count", count: pending_count)
    end

    def confirm_message
      t("applicants.show.documents.run_extraction_confirm", count: pending_count)
    end
  end
end
