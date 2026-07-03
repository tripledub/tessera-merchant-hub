# frozen_string_literal: true

class StreamOnboardingResponseJob < ApplicationJob
  queue_as :default

  def perform(session_id, user_message)
    session = OnboardingSession.find(session_id)
    Onboarding::ConversationEngine.respond(
      session: session,
      user_message: user_message,
      stream: true
    )
  end
end
