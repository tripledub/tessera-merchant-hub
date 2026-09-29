# frozen_string_literal: true

class Portal::SessionsController < Devise::SessionsController
  include Portal::AbuseProtection

  layout "portal"
  before_action -> { reject_oversized_portal_payload(REGISTRATION_PAYLOAD_LIMIT) }, only: :create
  rate_limit to: 10, within: 1.minute, with: :portal_rate_limited,
             store: portal_rate_limit_store, only: :create

  def after_sign_in_path_for(_resource)
    portal_root_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    new_applicant_user_session_path
  end
end
