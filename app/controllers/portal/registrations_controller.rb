# frozen_string_literal: true

class Portal::RegistrationsController < Devise::RegistrationsController
  include Portal::AbuseProtection

  layout "portal"
  before_action :load_invitation, only: %i[new create]
  before_action -> { reject_oversized_portal_payload(REGISTRATION_PAYLOAD_LIMIT) }, only: :create
  rate_limit to: 5, within: 10.minutes, with: :portal_rate_limited,
             store: portal_rate_limit_store, only: :create

  def create
    build_resource(sign_up_params)

    saved = ApplicantUser.transaction do
      next false unless resource.save

      invitation.claim!(resource)
      true
    end

    if saved
      set_flash_message! :notice, :signed_up_but_unconfirmed
      expire_data_after_sign_in!
      respond_with resource, location: after_inactive_sign_up_path_for(resource)
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  rescue ActiveRecord::RecordNotUnique, ApplicantInvitation::NotClaimable
    head :not_found
  end

  private

  def build_resource(hash = {})
    super(hash.merge(email: invitation.email))
    resource.applicant = invitation.applicant
  end

  def after_inactive_sign_up_path_for(_resource)
    new_applicant_user_session_path
  end

  def load_invitation
    self.invitation = ApplicantInvitation.find_usable_by_token(params[:invitation_token])
    unless invitation
      log_invalid_portal_access
      head :not_found
    end
  end

  attr_accessor :invitation

  helper_method :invitation

  def sign_up_params
    params.require(:applicant_user)
          .permit(:first_name, :last_name, :password, :password_confirmation)
          .merge(email: invitation.email)
  end
end
