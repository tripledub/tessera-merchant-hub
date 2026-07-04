# frozen_string_literal: true

class OnboardingChannel < ApplicationCable::Channel
  def subscribed
    session = OnboardingSession.find_by(id: params[:session_id])
    verified = verify_cable_token(params[:token], session)
    return reject if verified.nil?

    stream_from "onboarding:#{session.id}"
  end

  private

  def verify_cable_token(token, session)
    return nil if session.nil? || token.nil?

    data = Rails.application.message_verifier(:cable_auth).verified(token)
    data if data&.dig("session_id") == session.id
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
