# frozen_string_literal: true

# MH-408: "Not now" on the optional "set a password" banner. Remembered per user,
# so it stays gone across sign-ins and devices.
class Portal::PasswordPromptDismissalsController < Portal::BaseController
  def create
    current_applicant_user.touch(:password_prompt_dismissed_at)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("password-prompt") }
      format.html { redirect_to portal_root_path }
    end
  end
end
