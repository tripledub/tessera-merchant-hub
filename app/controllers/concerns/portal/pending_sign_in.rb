# frozen_string_literal: true

module Portal
  # The sign-in an applicant has started but not finished: which company, which
  # address, and the invitation (if any) it came from. It lives only in the
  # encrypted session cookie, never in a URL or a form, so nothing the browser
  # sends can change whose code is being checked (MH-405). It is forgotten after
  # thirty minutes.
  module PendingSignIn
    extend ActiveSupport::Concern

    SESSION_KEY = :portal_pending_sign_in
    PENDING_LIFETIME = 30.minutes

    Pending = Data.define(:applicant, :invitation_id, :invitation_token, :email)

    private

    def store_pending_sign_in(invitation:, token:)
      session[SESSION_KEY] = {
        "applicant_id" => invitation.applicant_id, "invitation_id" => invitation.id,
        "invitation_token" => token, "email" => invitation.email, "started_at" => Time.current.to_i
      }
      @pending_sign_in = nil
    end

    def clear_pending_sign_in
      session.delete(SESSION_KEY)
      @pending_sign_in = nil
    end

    # nil when there is nothing pending, or it is too old, or the company is gone.
    def pending_sign_in
      return @pending_sign_in if @pending_sign_in

      raw = session[SESSION_KEY]
      return unless raw.is_a?(Hash) && raw["started_at"].to_i > PENDING_LIFETIME.ago.to_i

      applicant = Applicant.find_by(id: raw["applicant_id"])
      return unless applicant && raw["email"].present?

      @pending_sign_in = Pending.new(
        applicant: applicant, invitation_id: raw["invitation_id"],
        invitation_token: raw["invitation_token"], email: raw["email"]
      )
    end
  end
end
