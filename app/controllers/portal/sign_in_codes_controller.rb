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
             store: portal_rate_limit_store, only: %i[start resend]
  rate_limit to: 10, within: 10.minutes, name: "verifications", with: :render_try_again_later,
             store: portal_rate_limit_store, only: :create
  before_action :require_pending_sign_in, only: %i[show create resend]

  CODE_FORMAT = /\A\d{#{ApplicantSignInCode::CODE_LENGTH}}\z/

  def start
    invitation = ApplicantInvitation.find_usable_by_token(params[:token])
    return render_dead_link(params[:token]) unless invitation

    result = ApplicantSignInCodes::Issue.call(applicant: invitation.applicant, email: invitation.email, invitation: invitation)
    return render_try_again_later if result.status == :rate_limited

    store_pending_sign_in(invitation: invitation, token: params[:token])
    redirect_to portal_sign_in_code_path, status: :see_other
  end

  def show
    @code_status = code_status
    case @code_status.state
    when :active then render :show
    when :locked then render :locked
    else render :expired
    end
  end

  def create
    return render_code_error(nil) unless submitted_code.match?(CODE_FORMAT)

    result = ApplicantSignInCodes::Verify.call(applicant: pending_sign_in.applicant, email: pending_sign_in.email, code: submitted_code)
    case result.status
    when :verified then complete_sign_in(result.applicant_user)
    when :wrong then render_code_error(result.attempts_left)
    else redirect_to portal_sign_in_code_path, status: :see_other
    end
  end

  def resend
    invitation = nil
    if pending_sign_in.invitation_id
      invitation = ApplicantInvitation.usable.find_by(id: pending_sign_in.invitation_id)
      return render_dead_link(pending_sign_in.invitation_token) unless invitation
    end

    result = ApplicantSignInCodes::Issue.call(applicant: pending_sign_in.applicant, email: pending_sign_in.email, invitation: invitation)
    return render_try_again_later if result.status == :rate_limited

    redirect_to portal_sign_in_code_path, status: :see_other
  end

  private

  def require_pending_sign_in
    return if pending_sign_in

    redirect_to new_applicant_user_session_path, alert: t("portal.sign_in_codes.no_pending")
  end

  def code_status
    ApplicantSignInCodes::Status.call(applicant: pending_sign_in.applicant, email: pending_sign_in.email)
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
