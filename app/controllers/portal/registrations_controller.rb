# frozen_string_literal: true

class Portal::RegistrationsController < Devise::RegistrationsController
  layout "portal"
  before_action :load_invitation, only: %i[new create]

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
  rescue ApplicantInvitation::NotClaimable
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
    head :not_found unless invitation
  end

  attr_accessor :invitation

  helper_method :invitation

  def sign_up_params
    params.require(:applicant_user)
          .permit(:first_name, :last_name, :password, :password_confirmation)
          .merge(email: invitation.email)
  end
end
