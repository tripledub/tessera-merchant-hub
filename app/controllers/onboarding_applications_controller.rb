# frozen_string_literal: true

class OnboardingApplicationsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) }
  expose(:onboarding_application) { applicant.onboarding_application }

  def show
    head(:not_found) and return unless onboarding_application

    authorize onboarding_application
  end
end
