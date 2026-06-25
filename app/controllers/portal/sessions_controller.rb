# frozen_string_literal: true

class Portal::SessionsController < Devise::SessionsController
  layout "portal"

  def after_sign_in_path_for(_resource)
    portal_root_path
  end
end
