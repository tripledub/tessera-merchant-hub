# frozen_string_literal: true

class Portal::SessionsController < Devise::SessionsController
  include Portal::AbuseProtection
  include Portal::InvitationPage

  layout "applicant"
  prepend_before_action :require_no_authentication, only: %i[new create password]
  before_action :prevent_caching_and_indexing, only: %i[new password]
  before_action -> { reject_oversized_portal_payload(REGISTRATION_PAYLOAD_LIMIT) }, only: :create
  rate_limit to: 10, within: 1.minute, with: :portal_rate_limited,
             store: portal_rate_limit_store, only: :create

  # /portal/sign_in is the "Welcome back" page: ask for an emailed code (MH-406).
  # Devise also re-renders this action, as a POST, after a failed password
  # sign-in, and that has to keep showing the password form.
  def new
    return password_form if request.post?

    self.resource = resource_class.new
    render :new
  end

  def password
    password_form
  end

  def after_sign_in_path_for(_resource)
    portal_root_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    new_applicant_user_session_path
  end

  private

  def password_form
    self.resource = resource_class.new(sign_in_params)
    clean_up_passwords(resource)
    render :password
  end
end
