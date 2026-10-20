# frozen_string_literal: true

# Devise's reset pages for applicants. The only change (MH-408) is that the edit
# and update pages are open to a SIGNED-IN applicant too: "Set a password" on the
# dashboard emails them a link, and they open it in the browser they are already
# signed in to. The reset token is what proves who is setting the password. Asking
# for a reset (new, create) still turns signed-in users away.
class Portal::PasswordsController < Devise::PasswordsController
  skip_before_action :require_no_authentication, only: %i[edit update]

  helper_method :first_password?

  protected

  def after_resetting_password_path_for(resource)
    sign_in_after_reset_password? ? portal_root_path : super
  end

  # True when the person this link is for has no password yet, so the page can
  # say it is optional rather than talk about a reset.
  def first_password?
    token = resource&.reset_password_token.presence || params[:reset_password_token].presence
    return false unless token

    user = ApplicantUser.with_reset_password_token(token)
    user.present? && !user.password_set?
  end
end
