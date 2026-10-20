# frozen_string_literal: true

# MH-408: "Set a password" / "Change password" from the dashboard. It emails the
# signed-in applicant the standard reset link, to their own address only, so a
# password can only be set by someone who controls the mailbox. The person then
# sets it on the reset page (Portal::PasswordsController).
class Portal::PasswordSetupsController < Portal::BaseController
  include Portal::AbuseProtection

  SESSION_KEY = :password_link_sent

  rate_limit to: 3, within: 1.hour, by: -> { current_applicant_user.id }, with: :too_many_requests_back_to_dashboard,
             store: portal_rate_limit_store, only: :create

  def create
    current_applicant_user.send_reset_password_instructions
    session[SESSION_KEY] = true
    redirect_to portal_root_path, status: :see_other
  end

  private

  def too_many_requests_back_to_dashboard
    redirect_to portal_root_path, alert: t("portal.password_setups.too_many"), status: :see_other
  end
end
