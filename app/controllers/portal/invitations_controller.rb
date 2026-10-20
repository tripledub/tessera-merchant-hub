# frozen_string_literal: true

class Portal::InvitationsController < ApplicationController
  include Portal::AbuseProtection
  include Portal::InvitationPage

  layout "applicant"

  skip_before_action :authenticate_user!
  rate_limit to: 20, within: 1.minute, with: :portal_rate_limited,
             store: portal_rate_limit_store, only: :show

  def show
    @invitation = ApplicantInvitation.find_usable_by_token(params[:token])
    return render_dead_link(params[:token]) unless @invitation

    prevent_caching_and_indexing
  end
end
