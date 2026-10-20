# frozen_string_literal: true

# "Request a new link" on the dead-link page. Whatever the token is, the
# answer is the same, so it cannot be used to find out which tokens exist.
class Portal::InvitationRenewalsController < ApplicationController
  include Portal::AbuseProtection
  include Portal::InvitationPage

  layout "applicant"

  skip_before_action :authenticate_user!
  rate_limit to: 5, within: 10.minutes, with: :portal_rate_limited,
             store: portal_rate_limit_store, only: :create

  def create
    SecurityEventLogger.log(event: "portal.invitation_renewal_requested", request: request)
    ApplicantInvitations::Renewal.call(token: params[:token])
    prevent_caching_and_indexing
  end
end
