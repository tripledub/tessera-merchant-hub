# frozen_string_literal: true

class Portal::DashboardController < Portal::BaseController
  def show
    # The confirmation after "Set a password" is shown once, in the banner's place.
    @password_link_sent = session.delete(Portal::PasswordSetupsController::SESSION_KEY)
    @show_password_prompt = !@password_link_sent && current_applicant_user.password_prompt_due?
  end
end
