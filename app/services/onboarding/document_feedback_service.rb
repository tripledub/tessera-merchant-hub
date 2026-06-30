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

      @collection_service = DocumentCollectionService.new(@session)

      post_message(build_message)
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
        outstanding = @collection_service.outstanding_items
        if outstanding.any?
          remaining = outstanding.map { |item| item["label"] }.join(", ")
          "**#{filename}** received and processed successfully. Still needed: #{remaining}."
        else
          "**#{filename}** received and processed successfully."
        end
      end
    end

    def post_message(content)
      message = OnboardingMessage.create!(
        onboarding_session: @session,
        role: :bot,
        content: content,
        stage: "document_collection"
      )
      broadcast_message(message)
      message
    end

    def broadcast_message(message)
      Turbo::StreamsChannel.broadcast_append_to(
        @session,
        target: "onboarding_messages",
        partial: "onboarding/conversations/message",
        locals: { message: message }
      )
    end

    # Locks the session row so concurrent extraction jobs can't both observe
    # all_received? == true and both advance the stage / post the completion message.
    def complete_session_if_finished
      completed_now = @session.with_lock do
        next false if @session.completed?
        next false unless @collection_service.all_received?

        Onboarding::StateMachine.advance!(@session)
        true
      end

      post_message("That's all the documents we need — your application is now complete!") if completed_now
    end
  end
end
