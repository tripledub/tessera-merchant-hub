# frozen_string_literal: true

class Portal::InvitationsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    invitation = ApplicantInvitation.find_usable_by_token(params[:token])
    return head :not_found unless invitation

    redirect_to new_applicant_user_registration_path(invitation_token: params[:token])
  end
end
