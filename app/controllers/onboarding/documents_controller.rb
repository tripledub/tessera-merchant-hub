# frozen_string_literal: true

module Onboarding
  class DocumentsController < Portal::BaseController
    def create
      files = Array(params.dig(:kyc_document, :files)).compact_blank

      if files.blank?
        @message = "Choose at least one file to upload."
        @type = :error
      else
        @results = files.map { |file| upload_document(file) }
        saved = @results.count(&:success?)
        @message = saved.zero? ? "Choose at least one supported file to upload." : "Uploaded #{saved} #{'document'.pluralize(saved)}."
        @type = saved.zero? ? :error : :success

        if saved.positive? && current_applicant.onboarding_session&.document_collection?
          @bot_message = OnboardingMessage.create!(
            onboarding_session: current_applicant.onboarding_session,
            role: :bot,
            content: "Received #{saved} #{'file'.pluralize(saved)} — processing now...",
            stage: "document_collection"
          )
        end
      end

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to portal_onboarding_path, notice: @message }
      end
    end

    private

    UploadResult = Struct.new(:filename, :success?, :error, keyword_init: true)

    def upload_document(file)
      filename = file.respond_to?(:original_filename) ? file.original_filename : file.to_s
      document = current_applicant.kyc_documents.build(status: :pending)

      unless document.save(validate: false)
        return UploadResult.new(filename: filename, success?: false, error: document.errors.full_messages.to_sentence)
      end

      document.file.attach(file)

      unless document.file.attached? && document.valid?
        error = document.errors.full_messages.to_sentence.presence || "could not be uploaded"
        document.destroy
        return UploadResult.new(filename: filename, success?: false, error: error)
      end

      ClassifyKycDocumentJob.perform_later(document.id)
      UploadResult.new(filename: filename, success?: true, error: nil)
    rescue ArgumentError, ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature => e
      document&.destroy
      UploadResult.new(filename: filename, success?: false, error: e.message)
    end
  end
end
