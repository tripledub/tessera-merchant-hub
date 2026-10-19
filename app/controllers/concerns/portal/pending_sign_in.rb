# frozen_string_literal: true

module Portal
  # The sign-in an applicant has started but not finished: which company, which
  # address, and the invitation (if any) it came from. It lives only in the
  # encrypted session cookie, never in a URL or a form, so nothing the browser
  # sends can change whose code is being checked (MH-405). It is forgotten after
  # thirty minutes.
  #
  # For a returning applicant (MH-406) an address with no account gets a "decoy"
  # of the same shape, so the cookie a visitor can see has the same layout and
  # length whether or not the address is registered: every field is always
  # present, the flags are 0 or 1, and the real flow keeps the same attempt and
  # send counters (as a mirror; the database is what it trusts).
  module PendingSignIn
    extend ActiveSupport::Concern

    SESSION_KEY = :portal_pending_sign_in
    PENDING_LIFETIME = 30.minutes

    Pending = Data.define(:applicant, :invitation_id, :invitation_token, :email, :returning, :decoy, :fresh,
                          :attempts, :sent_at)

    private

    def store_pending_sign_in(email:, applicant_id:, invitation: nil, token: nil, returning: false, decoy: false,
                              attempts: 0, sent_at: nil)
      now = Time.current.to_i
      session[SESSION_KEY] = {
        "applicant_id" => applicant_id, "invitation_id" => invitation&.id, "invitation_token" => token,
        "email" => email, "started_at" => now, "returning" => returning ? 1 : 0, "decoy" => decoy ? 1 : 0,
        "fresh" => 1, "attempts" => attempts, "sent_at" => sent_at || [ now ]
      }
      @pending_sign_in = nil
    end

    def update_pending_sign_in(changes)
      session[SESSION_KEY] = session[SESSION_KEY].merge(changes)
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

      decoy = raw["decoy"].to_i == 1
      applicant = decoy ? nil : Applicant.find_by(id: raw["applicant_id"])
      return unless raw["email"].present? && (decoy || applicant)

      @pending_sign_in = Pending.new(
        applicant: applicant, invitation_id: raw["invitation_id"], invitation_token: raw["invitation_token"],
        email: raw["email"], returning: raw["returning"].to_i == 1, decoy: decoy, fresh: raw["fresh"].to_i == 1,
        attempts: raw["attempts"].to_i, sent_at: Array(raw["sent_at"]).map(&:to_i)
      )
    end
  end
end
