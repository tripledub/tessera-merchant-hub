# frozen_string_literal: true

# MH-422: tells an open onboarding chat that a document has been dealt with. Saves the
# outcome message (Onboarding::DocumentOutcomeMessage) and sends it, rendered, to the
# session's channel, where the page adds it and refreshes the checklist and notices.
# Failing to tell the chat must never fail, or change the state of, the document.
module OnboardingChatNotifier
  extend ActiveSupport::Concern

  private

  def notify_onboarding_chat(document)
    message = Onboarding::DocumentOutcomeMessage.record!(document)
    return unless message

    ActionCable.server.broadcast(
      "onboarding:#{message.onboarding_session_id}",
      { type: "document_update", bot_message: MarkdownRenderer.call(message.content) }
    )
  rescue StandardError => e
    Rails.logger.warn("[OnboardingChatNotifier] could not tell the chat: #{e.class}")
  end
end
