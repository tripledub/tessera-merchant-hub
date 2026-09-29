# frozen_string_literal: true

class Portal::InvitationsController < ApplicationController
  include Portal::AbuseProtection

  skip_before_action :authenticate_user!
  rate_limit to: 20, within: 1.minute, with: :portal_rate_limited,
             store: portal_rate_limit_store, only: :show

  def show
    invitation = ApplicantInvitation.find_usable_by_token(params[:token])
    unless invitation
      log_invalid_portal_access
      return head :not_found
    end

    redirect_to new_applicant_user_registration_path(invitation_token: params[:token])
  end
end
