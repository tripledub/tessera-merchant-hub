# frozen_string_literal: true

class Onboarding::SessionsController < Devise::SessionsController
  layout "onboarding"

  def after_sign_in_path_for(_resource)
    onboarding_root_path
  end
end
