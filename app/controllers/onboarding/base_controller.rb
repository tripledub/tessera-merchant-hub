# frozen_string_literal: true

class Onboarding::BaseController < ApplicationController
  skip_before_action :authenticate_user!
  layout "onboarding"
  before_action :authenticate_applicant_user!

  private

  def current_applicant
    current_applicant_user&.applicant
  end
  helper_method :current_applicant
end
