# frozen_string_literal: true

module Onboarding
  class DocumentFeedbackService
    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
      @applicant = document.applicant
      @session = @applicant.onboarding_session
    end

    def call
      return unless @session&.document_collection?

      message_text = build_message
      message = OnboardingMessage.create!(
        onboarding_session: @session,
        role: :bot,
        content: message_text,
        stage: "document_collection"
      )

      broadcast_message(message)
      complete_session_if_finished
    end

    private

    def build_message
      filename = @document.file.filename

      if @document.error?
        "There was a problem processing **#{filename}**. Please try uploading it again."
      elsif @document.match_confidence.present? && @document.match_confidence < 0.80
        "I've processed **#{filename}**, but the name doesn't closely match what was declared. Please check this is the correct document."
      else
        outstanding = DocumentCollectionService.outstanding_items(@session)
        if outstanding.any?
          remaining = outstanding.map { |item| item["label"] }.join(", ")
          "**#{filename}** received and processed successfully. Still needed: #{remaining}."
        else
          "**#{filename}** looks good — that's all the documents we need. Your application is now complete!"
        end
      end
    end

    def broadcast_message(message)
      Turbo::StreamsChannel.broadcast_append_to(
        "onboarding_#{@session.id}_documents",
        target: "onboarding_messages",
        partial: "onboarding/conversations/message",
        locals: { message: message }
      )
    end

    def complete_session_if_finished
      return unless DocumentCollectionService.all_received?(@session)

      @session.update!(status: :completed)
    end
  end
end
