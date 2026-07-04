# frozen_string_literal: true

class OnboardingChannel < ApplicationCable::Channel
  def subscribed
    session = OnboardingSession.find_by(id: params[:session_id])

    if session.nil? || session.applicant_id != current_applicant_user.applicant_id
      reject
    else
      stream_from "onboarding:#{session.id}"
    end
  end
end
