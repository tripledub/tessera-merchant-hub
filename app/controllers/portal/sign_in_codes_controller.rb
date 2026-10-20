# frozen_string_literal: true

# MH-405: signing in with a one-time code emailed to the applicant. Which address
# and company the code belongs to comes from the session (PendingSignIn), never
# from the request; the code service (MH-404) holds the real limits.
class Portal::SignInCodesController < ApplicationController
  include Portal::AbuseProtection
  include Portal::InvitationPage
  include Portal::PendingSignIn

  layout "applicant"

  skip_before_action :authenticate_user!
  before_action :prevent_caching_and_indexing
  before_action -> { reject_oversized_portal_payload(REGISTRATION_PAYLOAD_LIMIT) }, only: :create
  # Per address, over and above the per-address limits of the code service. The
  # cache is not a dependable counter, so this is best effort.
  rate_limit to: 5, within: 10.minutes, name: "requests", with: :render_try_again_later,
             store: portal_rate_limit_store, only: %i[start request_code resend]
  # Every address, known or not, hits the same wall at the same count (MH-406). The
  # cache key is a keyed fingerprint, never the address.
  rate_limit to: 10, within: 1.hour, by: -> { address_limit_key }, name: "address", with: :render_try_again_later,
             store: portal_rate_limit_store, only: :request_code
  rate_limit to: 10, within: 10.minutes, name: "verifications", with: :render_try_again_later,
             store: portal_rate_limit_store, only: :create
  before_action :require_pending_sign_in, only: %i[show create resend]

  CODE_FORMAT = /\A\d{#{ApplicantSignInCode::CODE_LENGTH}}\z/
  # An answer takes this long whether or not the address has an account.
  RESPONSE_FLOOR = 0.4
  # What the countdown shows straight after asking for a code, whatever the real gap.
  FIXED_COUNTDOWN = 30
  MAX_EMAIL_LENGTH = 254

  def start
    invitation = ApplicantInvitation.find_usable_by_token(params[:token])
    return render_dead_link(params[:token]) unless invitation

    result = ApplicantSignInCodes::Issue.call(applicant: invitation.applicant, email: invitation.email, invitation: invitation)
    return render_try_again_later if result.status == :rate_limited

    store_pending_sign_in(email: invitation.email, applicant_id: invitation.applicant_id, invitation: invitation,
                          token: params[:token])
    redirect_to portal_sign_in_code_path, status: :see_other
  end

  # A returning applicant asks for a code (MH-406). Whatever the address, the
  # visitor is sent to the same page with the same headers and cookie shape.
  def request_code
    return render_email_error unless valid_email?(requested_email)

    limited = MinimumDuration.call(RESPONSE_FLOOR) { start_returning(requested_email) }
    return render_try_again_later if limited

    redirect_to portal_sign_in_code_path, status: :see_other
  end

  def show
    @code_status = code_status
    @code_status = @code_status.with(resend_in: FIXED_COUNTDOWN) if consume_fresh_start && @code_status.state == :active
    case @code_status.state
    when :active then render :show
    when :locked then render :locked
    else render :expired
    end
  end

  def create
    return render_code_error(nil) unless submitted_code.match?(CODE_FORMAT)
    return verify_decoy if pending_sign_in.decoy

    result = ApplicantSignInCodes::Verify.call(applicant: pending_sign_in.applicant, email: pending_sign_in.email, code: submitted_code)
    case result.status
    when :verified then complete_sign_in(result.applicant_user)
    when :wrong
      update_pending_sign_in("attempts" => ApplicantSignInCode::MAX_ATTEMPTS - result.attempts_left)
      render_code_error(result.attempts_left)
    when :locked
      update_pending_sign_in("attempts" => ApplicantSignInCode::MAX_ATTEMPTS)
      redirect_to portal_sign_in_code_path, status: :see_other
    else redirect_to portal_sign_in_code_path, status: :see_other
    end
  end

  def resend
    return resend_decoy if pending_sign_in.decoy

    invitation = nil
    if pending_sign_in.invitation_id
      invitation = ApplicantInvitation.usable.find_by(id: pending_sign_in.invitation_id)
      return render_dead_link(pending_sign_in.invitation_token) unless invitation
    end

    result = ApplicantSignInCodes::Issue.call(applicant: pending_sign_in.applicant, email: pending_sign_in.email, invitation: invitation)
    return render_try_again_later if result.status == :rate_limited

    mirror_send if result.status == :sent
    redirect_to portal_sign_in_code_path, status: :see_other
  end

  private

  def requested_email
    @requested_email ||= params[:email].is_a?(String) ? params[:email].strip.downcase : ""
  end

  def valid_email?(email)
    email.length.between?(1, MAX_EMAIL_LENGTH) && email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def address_limit_key
    valid_email?(requested_email) ? SecurityEventLogger.fingerprint(requested_email) : "invalid:#{request.remote_ip}"
  end

  def render_email_error
    @email_error = true
    render "applicant_users/sessions/new", status: :unprocessable_content
  end

  # True when the address has asked for too many codes. Both branches leave the
  # same shape of session behind, and take the same lookups.
  def start_returning(email)
    user = ApplicantUser.find_by(email: email)
    SecurityEventLogger.log_event(
      event: "portal.sign_in.start", email_fingerprint: SecurityEventLogger.fingerprint(email), account_found: user.present?
    )

    prior = prior_sends_for(email)
    if user
      return true if ApplicantSignInCodes::Issue.call(applicant: user.applicant, email: email).status == :rate_limited
    elsif prior.status == :rate_limited
      return true
    end

    store_pending_sign_in(
      email: email, applicant_id: user ? user.applicant_id : SecureRandom.uuid, returning: true, decoy: user.nil?,
      attempts: prior.attempts, sent_at: prior.sent_at
    )
    false
  end

  # Asking again inside the thirty-second gap keeps what was there (no new code,
  # attempts as they were); asking later is a fresh send, as for the real service.
  def prior_sends_for(email)
    existing = pending_sign_in
    unless existing&.returning && existing.email == email
      now = Time.current.to_i
      return ApplicantSignInCodes::Decoy::Outcome.new(status: :sent, attempts: 0, attempts_left: nil, sent_at: [ now ], retry_after: nil)
    end

    ApplicantSignInCodes::Decoy.resend(sent_at: existing.sent_at, attempts: existing.attempts)
  end

  def verify_decoy
    outcome = ApplicantSignInCodes::Decoy.verify(attempts: pending_sign_in.attempts, sent_at: pending_sign_in.sent_at, code: submitted_code)
    case outcome.status
    when :wrong
      update_pending_sign_in("attempts" => outcome.attempts)
      render_code_error(outcome.attempts_left)
    when :locked
      update_pending_sign_in("attempts" => ApplicantSignInCode::MAX_ATTEMPTS)
      redirect_to portal_sign_in_code_path, status: :see_other
    else redirect_to portal_sign_in_code_path, status: :see_other
    end
  end

  def resend_decoy
    outcome = ApplicantSignInCodes::Decoy.resend(sent_at: pending_sign_in.sent_at, attempts: pending_sign_in.attempts)
    return render_try_again_later if outcome.status == :rate_limited

    update_pending_sign_in("attempts" => 0, "sent_at" => outcome.sent_at) if outcome.status == :sent
    redirect_to portal_sign_in_code_path, status: :see_other
  end

  # The real flow keeps the same counters in the session as the decoy does, so
  # the cookie behaves the same for both.
  def mirror_send
    sent = (pending_sign_in.sent_at + [ Time.current.to_i ]).last(ApplicantSignInCodes::Issue::DAILY_CAP)
    update_pending_sign_in("attempts" => 0, "sent_at" => sent)
  end

  # The first look at the page after asking for a code shows a fixed countdown.
  def consume_fresh_start
    return false unless pending_sign_in.returning && pending_sign_in.fresh

    update_pending_sign_in("fresh" => 0)
    true
  end

  def require_pending_sign_in
    return if pending_sign_in

    redirect_to new_applicant_user_session_path, alert: t("portal.sign_in_codes.no_pending")
  end

  def code_status
    if pending_sign_in.decoy
      ApplicantSignInCodes::Decoy.status(attempts: pending_sign_in.attempts, sent_at: pending_sign_in.sent_at)
    else
      ApplicantSignInCodes::Status.call(applicant: pending_sign_in.applicant, email: pending_sign_in.email)
    end
  end

  # The boxes are filled by script; only the assembled digits are sent.
  def submitted_code
    value = params[:code]
    value.is_a?(String) ? value.gsub(/[\s-]/, "") : ""
  end

  def render_code_error(attempts_left)
    @attempts_left = attempts_left
    @code_status = code_status
    render :show, status: :unprocessable_content
  end

  def render_try_again_later
    SecurityEventLogger.log(event: "portal.rate_limited", request: request)
    render "portal/sign_in_codes/try_again_later", status: :too_many_requests
  end

  # One transaction: the user, then the invitation. If the invitation is no
  # longer usable, or the address belongs to another company's user, the link is
  # dead and nobody is signed in (as with registration).
  def complete_sign_in(existing_user)
    # A returning applicant only ever signs in to an account that exists.
    return redirect_to(portal_sign_in_code_path, status: :see_other) if pending_sign_in.returning && existing_user.nil?

    user = ApplicantUser.transaction do
      found = existing_user || build_user
      claim_invitation!(found)
      found
    end

    reset_session
    sign_in(:applicant_user, user)
    redirect_to portal_root_path, status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ApplicantInvitation::NotClaimable
    render_dead_link(pending_sign_in.invitation_token)
  end

  def build_user
    ApplicantUser.new(applicant: pending_sign_in.applicant, email: pending_sign_in.email).tap do |user|
      user.skip_confirmation!
      user.save!
    end
  end

  def claim_invitation!(user)
    return unless pending_sign_in.invitation_id

    invitation = ApplicantInvitation.usable.find_by(id: pending_sign_in.invitation_id)
    raise ApplicantInvitation::NotClaimable unless invitation

    invitation.claim!(user)
  end

  helper_method :pending_sign_in, :back_path

  def back_path
    token = pending_sign_in&.invitation_token
    token ? portal_invitation_path(token) : new_applicant_user_session_path
  end
end
