# frozen_string_literal: true

class Portal::RegistrationsController < Devise::RegistrationsController
  layout "portal"

  private

  def sign_up_params
    params.require(:applicant_user).permit(:first_name, :last_name, :email, :password, :password_confirmation)
  end

  def build_resource(hash = {})
    super
    return if resource.applicant.present?

    resource.applicant = Applicant.new(
      name: "#{hash[:first_name]} #{hash[:last_name]}".strip,
      status: :pending
    )
  end

  def after_sign_up_path_for(_resource)
    portal_root_path
  end
end
