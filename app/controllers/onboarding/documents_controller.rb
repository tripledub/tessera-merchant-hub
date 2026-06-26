# frozen_string_literal: true

module Onboarding
  class DocumentsController < Portal::BaseController
    def create
      files = Array(params.dig(:kyc_document, :files)).compact_blank
      @message = upload_documents(files)
      @type = files.blank? ? :error : :success

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to portal_onboarding_path, notice: @message }
      end
    end

    private

    def upload_documents(files)
      return "Choose at least one file to upload." if files.blank?

      saved = files.count { |file| create_document(file) }
      return "Choose at least one supported file to upload." if saved.zero?

      "Uploaded #{saved} #{'document'.pluralize(saved)}."
    end

    def create_document(file)
      document = current_applicant.kyc_documents.build(status: :pending)
      return false unless document.save(validate: false)

      document.file.attach(file)
      return destroy_invalid_document(document) unless document.file.attached? && document.valid?

      ClassifyKycDocumentJob.perform_later(document.id)
      true
    rescue ArgumentError, ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature
      destroy_invalid_document(document)
    end

    def destroy_invalid_document(document)
      document.destroy
      false
    end
  end
end
