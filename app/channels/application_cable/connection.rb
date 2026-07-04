# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_applicant_user

    def connect
      # Warden may not have a session when AnyCable Go doesn't forward the cookie header.
      # Channel-level auth (OnboardingChannel) verifies a signed token instead.
      self.current_applicant_user = env["warden"]&.user(:applicant_user)
    end
  end
end
